{ lib, stdenvNoCC, makeWrapper, python3, quickshell, hyprland, systemd, coreutils, qt6, src }:
stdenvNoCC.mkDerivation {
  pname = "cedar-shell";
  version = "1.14";
  inherit src;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/share/cedar $out/bin
    # Use the same explicit publication inventory as Arch and tarball installs.
    ${python3}/bin/python3 - "$out/share/cedar" <<'PY'
import json, pathlib, shutil, sys
out = pathlib.Path(sys.argv[1])
for name in json.loads(pathlib.Path('data/source-files.json').read_text()):
    dest = out / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(name, dest)
PY
    makeWrapper ${python3}/bin/python3 $out/bin/cedar \
      --add-flags "$out/share/cedar/scripts/distribution.py" \
      --prefix PATH : ${lib.makeBinPath [ python3 quickshell hyprland systemd coreutils ]} \
      --prefix QML_IMPORT_PATH : "${qt6.qt5compat}/lib/qt-6/qml:${qt6.qtmultimedia}/lib/qt-6/qml" \
      --prefix QT_PLUGIN_PATH : "${qt6.qtsvg}/lib/qt-6/plugins:${qt6.qtimageformats}/lib/qt-6/plugins"
  '';
  meta = {
    description = "CEDAR desktop shell; adoption is explicit and reversible";
    homepage = "https://github.com/EMQOutlaw/Cedar-Shell";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
    mainProgram = "cedar";
  };
}
