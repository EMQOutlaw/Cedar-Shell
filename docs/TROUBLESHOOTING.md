# Troubleshooting and release notes for older candidates

These notes moved out of the README so the front page can stay short. They
are kept because people on older checkouts still hit them.

## Updating a checkout

**Field Station → Update CEDAR** and `cedar installer --update` now do the whole
update in the CEDAR Installer window: an Update stage fetches the newest
CEDAR with visible steps (fast-forward of the checkout, or the latest
verified release when there is no checkout; an unreadable `ORIG_HEAD` is
cleared), explains any stop with what to do and, where a fix is safe, a
button that applies it; then the installer hands the desktop back from a
running CEDAR session, installs, and starts CEDAR again. See "Updating" in
docs/INSTALLATION.md. The notes below describe the manual steps that still
work.

`git pull` updates the checkout; a successful installation updates the
installed `cedar` command. If setup was canceled or failed, the previous
installed version remains selected. If Git reports local changes or
divergent history, stop and preserve your edits; do not reset or delete the
checkout. The installer copies only the reviewed source inventory, so an
accidentally nested clone or local settings file is not included and is
left untouched.

**Already running a kept CEDAR session?** Restore its desktop integration
before updating the installed release:

```bash
"$HOME/.local/bin/cedar" restore && cd "$HOME/cedar-shell" && git pull --ff-only && bash ./install.sh
```

From the desktop, **Field Station → Update CEDAR** runs these same steps in
the installer window; `cedar installer --update --no-gui` prints them in a
terminal. A refused fast-forward leaves the checkout and the desktop as they
were, and the window says what to do next.

## Messages from older candidates

- **“Omarchy activation requires omarchy.”** An old installed `cedar` command
  is still selected. Finish installing the current candidate, then run
  `cedar try` again. Do not install Omarchy to resolve this.
- **“Cannot inspect a same-user process”** (before 0.1.0-dev.8): an
  unrelated application protected its executable metadata. Update the
  checkout and reinstall; no system permission changes are needed. CEDAR
  still refuses to switch a running release or change desktop providers
  when their identity or lock state cannot be verified.
- **Try reports “Expecting value: line 1 column 1”** (candidate 8 with native
  Noctalia): update to 0.1.0-dev.9 or newer and try again. Quickshell can
  return a plain-text message even in JSON mode when it has no instances;
  candidate 9 handles that and Noctalia 5.2.1's actual version format. This
  does not require installing Omarchy, stopping Noctalia or deleting the
  checkout.
- **`CEDAR: 'root'` after trial approval** (candidate 9): update to
  0.1.0-dev.10 or newer. This was a missing internal installation-path
  field, not a request to run as root; it occurred before the trial
  changed any provider settings.

## What the candidates added

- **0.1.0-dev.11** introduced the launcher and lockscreen choices: CEDAR Go
  for the application shortcut and, on native Noctalia 5.2.1, Trailwatch as
  the locker. Trailwatch first checks your password in a local window, then
  opens one real lockscreen test; unlock normally to continue. Your previous
  locker stays configured until that secure unlock succeeds and the sleep
  bridge is ready. The Trailwatch replacement uses **hypridle 0.1.7** for
  logind lock and sleep requests through a private instance with no extra
  idle timers; Noctalia's ordinary idle timings are retained. An existing
  independent idle daemon, special locked-state timeout or unreviewed runtime
  is left for review instead of being silently replaced.
- **0.1.0-dev.12** added Settings → Desktop Setup, quiet controls, lazy
  views, shared application/network subscriptions and stricter handoff
  journals. Desktop Setup uses the same backend as the terminal installer;
  it does not bypass local authentication, ownership checks or separate
  login approval. See [implementation and verification](IMPLEMENTATION-REPORT.md).

## The classic terminal installer

`bash ./install.sh` now opens the CEDAR Installer (see
[INSTALLATION.md](INSTALLATION.md)). The reviewed terminal flow is still
there and is used automatically for its own flags:

- `bash ./install.sh --plan` inspects without installing.
- `--approve-install-only` copies the files without preparing dependencies
  or touching the desktop. There is no generic yes flag authorizing takeover.
- `python3 scripts/distribution.py dependencies` shows the required and
  feature dependency plan; `--include-recommended` also requests the
  recommended fonts, which otherwise use readable fallbacks and never block
  installation. Package changes require both `--approve-packages
  --approve-system-upgrade`, which authorize a full supported upgrade.
- Set `CEDAR_CLASSIC_INSTALL=1` to force the terminal flow with its
  Install Only / preview / trial menu.

A provided private candidate archive installs the same way: extract it,
open a terminal in the extracted `cedar-shell` folder, run `bash ./install.sh`.

## Package preparation

Automatic dependency preparation recognizes **Arch Linux, CachyOS and
Omarchy on x86_64**, using the repositories you already have. It checks that
each package exists before asking permission. No AUR helper or repository is
silently added; no replacement compositor, driver or service provider is
requested. `pacman -Syu` performs a full system upgrade along with the new
packages. With pacman, a missing Python can be installed only after
approving that plan. On other distributions, provide the dependencies with
your own package manager; a machine with complete dependencies does not
need automatic package support.
