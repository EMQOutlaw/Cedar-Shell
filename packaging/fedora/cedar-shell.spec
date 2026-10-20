# CEDAR Shell: the reviewed release archive byte-identical under /usr/share/cedar
# plus the cedar command. No scriptlets, services, desktop entries or
# byte-compiled Python: the per-user activation is `cedar installer`, run by
# the user. scripts/build_packages.py rpm builds this from the published
# archive; scripts/publish_version.py keeps Version, Release and %%changelog in
# step with VERSION.
#
# Fedora runtime prerequisites are documented in packaging/README.md.
# This is a project-owned package, not an official Fedora submission.

# Keep every shipped file byte-identical to the release archive: no shebang
# rewriting, no .pyc files, and no debuginfo for a tree without binaries.
%undefine __brp_mangle_shebangs
%undefine __brp_python_bytecompile
%global debug_package %{nil}
# Do not let future distro buildroot policy rewrite reviewed payload files.
%global __os_install_post %{nil}

Name:           cedar-shell
Version:        1.11
Release:        1%{?dist}
Summary:        CEDAR desktop shell for Hyprland
# The first-party code carries no license by the owner's decision
# (docs/LICENSES.md). This LicenseRef is deliberately not the SPDX "Unlicense".
License:        LicenseRef-CEDAR-Unlicensed
URL:            https://github.com/EMQOutlaw/Cedar-Shell
Source0:        %{url}/releases/download/v%{version}/cedar-%{version}-x86_64.tar.gz
BuildArch:      noarch

Requires:       python3 >= 3.11
Requires:       quickshell
Requires:       hyprland
Requires:       qt6-qtdeclarative
Requires:       qt6-qtsvg
Requires:       python3-gobject
Requires:       systemd
Recommends:     NetworkManager
Recommends:     NetworkManager-libnm
Recommends:     python3-dbus
Recommends:     pulseaudio-utils
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
Recommends:     hypridle
Recommends:     grim
Recommends:     slurp
Recommends:     git
Recommends:     openssl
Recommends:     procps-ng
Suggests:       hyprsunset
Suggests:       jetbrains-mono-fonts-all

%description
CEDAR is a complete desktop shell for Hyprland: a bar, quick controls, a
calendar, searchable settings, notifications, a lock screen, network privacy
tools and a Gaming Mode. This package installs the reviewed release tree under
/usr/share/cedar and the cedar command. Run `cedar installer` as your user to
set up and activate your own copy; nothing is enabled system-wide.

%prep
%autosetup -n cedar-shell

%build
# Nothing to compile: QML and Python ship exactly as reviewed.

%install
install -d %{buildroot}%{_datadir}/cedar %{buildroot}%{_bindir}
cp -a . %{buildroot}%{_datadir}/cedar/
printf '#!/bin/sh\nexec python3 /usr/share/cedar/scripts/distribution.py "$@"\n' > %{buildroot}%{_bindir}/cedar
chmod 0755 %{buildroot}%{_bindir}/cedar
install -D -m 0644 licenses/Omarchy-MIT.txt %{buildroot}%{_licensedir}/%{name}/Omarchy-MIT.txt
install -D -m 0644 docs/LICENSES.md %{buildroot}%{_licensedir}/%{name}/LICENSES.md

%files
%{_bindir}/cedar
%{_datadir}/cedar/
%license %{_licensedir}/%{name}/Omarchy-MIT.txt
%doc %{_licensedir}/%{name}/LICENSES.md

%changelog
* Tue Oct 20 2026 CEDAR release automation <41898282+github-actions[bot]@users.noreply.github.com> - 1.11-1
- Automated release 1.11

* Tue Oct 20 2026 CEDAR release automation <41898282+github-actions[bot]@users.noreply.github.com> - 1.9-1
- Automated release 1.9

* Sat Oct 17 2026 CEDAR release automation <41898282+github-actions[bot]@users.noreply.github.com> - 1.8-1
- Automated release 1.8
