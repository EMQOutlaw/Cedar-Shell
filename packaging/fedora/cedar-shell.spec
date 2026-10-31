# CEDAR Shell for Fedora: the reviewed release archive byte-identical under
# /usr/share/cedar, the cedar command, and the Task Manager built from the
# archive's own sources. No scriptlets, services or login changes: the per-user
# activation is `cedar installer`, run by the user.
#
# This is a project-owned package, not an official Fedora submission, and there
# is no hosted dnf repository: build it with rpmbuild (docs/compatibility/PACKAGING.md)
# or take the RPM attached to a GitHub release, then `dnf install ./cedar-shell-*.rpm`.
# scripts/publish_version.py keeps Version, Release and the changelog in step with VERSION.
#
# Hyprland is in Fedora's repositories. A current Quickshell (0.3 or newer; Fedora
# 44+ ships a 0.2.1 snapshot CEDAR cannot load), hypridle on Fedora 42+ and
# hyprsunset are not: enable a repository that provides them before installing.
#
# rpmlint reports env-script-interpreter, non-executable-script and
# file-contains-current-date for the payload and arch-dependent-file-in-usr-share
# for the Task Manager binaries. Those follow from shipping the reviewed archive
# unchanged, with the binaries where the Arch package and task_manager.py expect
# them, and are accepted for this project-owned package.

# Keep every shipped file byte-identical to the release archive: no shebang
# rewriting and no .pyc files. The Task Manager binaries are stripped as usual.
%undefine __brp_mangle_shebangs
%undefine __brp_python_bytecompile
%global _python_bytecompile_extra 0
%global debug_package %{nil}

Name:           cedar-shell
Version:        1.17
Release:        1%{?dist}
Summary:        CEDAR desktop shell for Hyprland
# The first-party code carries no license by the owner's decision
# (docs/LICENSES.md). This LicenseRef is deliberately not the SPDX "Unlicense".
License:        LicenseRef-CEDAR-Unlicensed
URL:            https://github.com/EMQOutlaw/Cedar-Shell
# The release asset; its name says x86_64 but the archive holds sources only.
Source0:        %{url}/releases/download/v%{version}/cedar-%{version}-x86_64.tar.gz
ExclusiveArch:  x86_64 aarch64

# scripts/build_task_manager.py: g++, pkg-config, Qt6 Core/Network/Gui/Qml/Quick/
# QuickControls2/DBus development files and moc.
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
BuildRequires:  python3
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  desktop-file-utils

Requires:       python3 >= 3.11
Requires:       quickshell >= 0.3
Requires:       hyprland
Requires:       qt6-qtbase
Requires:       qt6-qtdeclarative
Requires:       qt6-qtsvg
Requires:       qt6-qtmultimedia
Requires:       qt6-qt5compat
Requires:       qt6-qtimageformats
Requires:       python3-gobject
Requires:       systemd
Recommends:     NetworkManager
Recommends:     NetworkManager-libnm
Recommends:     python3-dbus
Recommends:     pulseaudio-utils
Recommends:     wireplumber
Recommends:     wl-clipboard
Recommends:     brightnessctl
Recommends:     power-profiles-daemon
Recommends:     polkit
Recommends:     xdg-utils
Recommends:     gtk3
Recommends:     glib2
Recommends:     jq
Recommends:     cava
Recommends:     lm_sensors
# Fedora packaged hypridle for 40 and 41 only; a weak dependency is skipped when absent.
Recommends:     hypridle
Recommends:     grim
Recommends:     slurp
Recommends:     git
Recommends:     openssl
Recommends:     procps-ng
# Fedora does not package hyprsunset; CEDAR reports night light absent without it.
Suggests:       hyprsunset
Suggests:       cliphist

%description
CEDAR is a complete desktop shell for Hyprland: a bar, quick controls, a
calendar, searchable settings, notifications, a lock screen, network privacy
tools and a Gaming Mode. This package installs the reviewed release tree under
/usr/share/cedar, the cedar command and the CEDAR Task Manager. Run
`cedar installer` as your user to set up and activate your own copy; nothing is
enabled system-wide.

%prep
%autosetup -n cedar-shell

%build
# The QML and Python ship exactly as reviewed. Only the Task Manager compiles,
# outside the source tree so the payload stays identical to the archive. The
# build script chooses its own flags (-O2 -g), as the Arch package does.
python3 scripts/build_task_manager.py "$PWD/../task-manager-build"

%install
install -d %{buildroot}%{_datadir}/cedar %{buildroot}%{_bindir}
cp -a . %{buildroot}%{_datadir}/cedar/
printf '#!/bin/sh\nexec python3 /usr/share/cedar/scripts/distribution.py "$@"\n' > %{buildroot}%{_bindir}/cedar
chmod 0755 %{buildroot}%{_bindir}/cedar
install -D -m 0755 ../task-manager-build/cedar-taskd %{buildroot}%{_datadir}/cedar/libexec/cedar-taskd
install -D -m 0755 ../task-manager-build/cedar-task-manager %{buildroot}%{_datadir}/cedar/libexec/cedar-task-manager
printf '#!/bin/sh\nexec python3 /usr/share/cedar/scripts/task_manager.py "$@"\n' > %{buildroot}%{_bindir}/cedar-task-manager
chmod 0755 %{buildroot}%{_bindir}/cedar-task-manager
install -D -m 0644 data/applications/cedar-task-manager.desktop %{buildroot}%{_datadir}/applications/cedar-task-manager.desktop
install -D -m 0644 data/icons/cedar-shield.svg %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/cedar-shield.svg
install -D -m 0644 licenses/Omarchy-MIT.txt %{buildroot}%{_licensedir}/%{name}/Omarchy-MIT.txt
install -D -m 0644 licenses/Field-Notes-MIT.txt %{buildroot}%{_licensedir}/%{name}/Field-Notes-MIT.txt
install -D -m 0644 licenses/btop-Apache-2.0.txt %{buildroot}%{_licensedir}/%{name}/btop-Apache-2.0.txt
install -D -m 0644 docs/LICENSES.md %{buildroot}%{_licensedir}/%{name}/LICENSES.md

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/cedar-task-manager.desktop

%files
%{_bindir}/cedar
%{_bindir}/cedar-task-manager
%{_datadir}/cedar/
%{_datadir}/applications/cedar-task-manager.desktop
%{_datadir}/icons/hicolor/scalable/apps/cedar-shield.svg
%license %{_licensedir}/%{name}/Omarchy-MIT.txt
%license %{_licensedir}/%{name}/Field-Notes-MIT.txt
%license %{_licensedir}/%{name}/btop-Apache-2.0.txt
%doc %{_licensedir}/%{name}/LICENSES.md

%changelog
* Sat Oct 31 2026 EMQOutlaw <152599387+EMQOutlaw@users.noreply.github.com> - 1.17-1
- Fedora package built from the release archive, with the Task Manager
