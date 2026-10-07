# Shield

CEDAR Shield is a first-party application: its own window (a regular
toplevel that Hyprland tiles or floats), its own launcher entry and icon
(`cedar shield`, Go › Shield, the Shield tile in Quick Controls, `qs -c cedar
ipc call shield open`), a sidebar with Overview, Protections, Network,
Activity and Settings, and a detail view per protection. It is a presentation
over the Shield service: closing the window or restarting the shell changes
no protection, because the protections live in the services that own them.

The window is hosted by the shell process (one `LazyLoader`, created on open
and released on close) so it shares the live service, costs no second
process, and remembers its size in `~/.local/state/cedar/shield.json`.
Minimum 720×520; the sidebar becomes a tab strip under 860 px and the cards
go single-column under 640 px.

## Overview, in two seconds

The shield mark is the state: a geometric shield holding a cedar's
branching structure, one branch per protection in Shield's order, bottom to
top. Low contrast off, cedar green on, amber to check, ember failed. On open
the outline settles and the branches light outward in sequence (about 800
ms, once); when a protection turns on, one light travels from the trunk to
its branch and stops. Nothing animates while nothing changes.

Posture comes from the recommended set only:

| Posture | Means | Colour |
| --- | --- | --- |
| Protected | every recommended protection is on | cedar green |
| Attention required | a recommended protection is off (or weak, like opportunistic DoT) | amber |
| At risk | a protection failed (two firewall managers active), or services answer on every interface while the firewall is off | ember |

A missing VPN or a hardware Wi-Fi address never turns the shield amber;
they are informational unless the network profile recommends them.

## Twelve protections in four groups

Network: Firewall, Encrypted DNS, Network discovery, Local exposure.
Privacy: Private Wi-Fi address, IPv6 privacy, VPN. Session: Lock screen
privacy, Lock after inactivity. Services: Local-only mode, Clipboard
history, Activity trails. Each card says what it is, what is happening, and
which provider does it; its detail view holds the controls and a Technical
details block with the raw provider fields and the last verification time.

## Network profile

Trusted or Public, remembered per NetworkManager connection. Public
recommends more: encrypted DNS (strict), no discovery answers and temporary
IPv6 addresses join the firewall and session protections, and "Apply
recommended" runs the first missing one through its provider, one verified
step at a time. A network change triggers one fresh read (debounced), even
with the window closed, so the Quick Controls tile stays true; that can be
turned off in Shield's settings.

## Activity

Only what Shield observed: a protection changing state between two reads
(after a read, an action, a setting or a network change), an action and
its verified result or its failure, a network or profile change. Kept to
the last 100 entries in the state file. Nothing is invented to fill the page.

## The path, per protection

| Protection | Subsystem | Detect | State | Change | Verify | Rollback |
| --- | --- | --- | --- | --- | --- | --- |
| Firewall | firewalld, UFW or an nftables ruleset service | installed binaries and unit files, in that order; an active or configured manager is the owner | unit active/enabled, `/etc/ufw/ufw.conf` `ENABLED=`, `/etc/firewalld/firewalld.conf`, `/etc/nftables.conf` | the owner's native command under `pkexec`: `ufw --force enable` + `systemctl enable --now ufw`, or `systemctl enable --now firewalld|nftables` | the same detection again | the opposite command if the state did not change; a dismissed prompt leaves everything as it was |
| Encrypted DNS | systemd-resolved behind NetworkManager | `/etc/resolv.conf` → stub, resolved active, NetworkManager active | `resolvectl status` per link (`+DNSOverTLS`, servers) and the active connection's `connection.dns-over-tls`, `ipv4/ipv6.dns`, `ignore-auto-dns` | `nmcli connection modify` on the default-route connection (strict `yes` or `opportunistic`, provider servers with their TLS names, auto DNS ignored), then `nmcli device reapply`, falling back to `connection up` | resolved reports DoT and the provider's servers on that link | the captured connection fields are written back and reapplied |
| Private Wi-Fi address | NetworkManager Wi-Fi profile | a Wi-Fi device; the active or most recently used profile | `802-11-wireless.cloned-mac-address`: `stable`, `random`, `permanent` (hardware), `preserve` (system default) | `nmcli connection modify` on that profile | read back | the previous value is written back |
| IPv6 privacy | NetworkManager `ipv6.ip6-privacy` on the active connection | a connection | `-1/0/1/2` plus the kernel's `use_tempaddr` | `nmcli connection modify` + `device reapply` | read back | previous value written back |
| Network discovery | systemd-resolved mDNS/LLMNR responders (via NetworkManager `connection.mdns/llmnr`) and Avahi | resolved and the connection | `resolvectl status` Protocols flags, Avahi unit state | `nmcli connection modify` + reapply; Avahi stopped under pkexec when running | resolved flags and the unit read back | connection fields restored |
| Local exposure | the kernel's socket tables | always | `/proc/net/tcp`, `tcp6`, `udp`, `udp6` listeners classified as localhost / this network / every interface, with the owning process for this user's sockets | none (information) | — | — |
| VPN, lock privacy, local-only | NetworkManager, CEDAR settings | — | read-only here; their switches stay on their own pages | — | — | — |

What is deliberately not offered: DNS-over-HTTPS (neither resolved nor
NetworkManager speaks it, so plain DNS is never labelled DoH), MAC spoofing
scripts, starting a second firewall manager beside an active one, and any
change without a provider to verify it against.

## Privileges

Only the firewall needs root. `scripts/shield.py` asks through `pkexec`, so
the polkit agent prompts the user; without pkexec or an agent the card says
so and the switch is disabled. DNS and Wi-Fi changes go through NetworkManager
with the user's own permissions (polkit may prompt for system connections).
No credentials ever pass through the shell.

## Cost

Nothing polls. `scripts/shield.py` runs when the page opens, on "Check
again", after an action, and once (debounced 1.5 s) when the network state
changes while the page is open. A snapshot is one `capabilities` pass,
`resolvectl status`, three `nmcli` reads and a `/proc` scan; the listener
list is capped at 200 rows. Closing the page stops everything. The shield
mark animates only on a transition: one light travels from the trunk to the
protection's branch pair over ~400 ms and stops; the lit state is static.

## Tests

`tests/test_shield.py` (listener parsing and classification, resolvectl
parsing, provider mapping, policy maps, per-provider commands),
`tests/check_shield.py` (derived states from fixture provider data, headline,
page at three widths). Live changes to the firewall, DNS and Wi-Fi are not
exercised by tests; they are verified on a real machine with the provider's
own tools.
