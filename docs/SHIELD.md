# Shield

Settings › Shield (Go › Shield, `cedar settings shield`, `qs -c cedar ipc call
settings show shield`). One dominant object, the CEDAR shield, and a card per
protection. Every card shows what the provider that owns the protection
reports; a change goes through that provider's own interface, is verified by
reading the provider again, and is rolled back when verification fails. The
card never shows success before the provider does.

## The path, per protection

| Protection | Subsystem | Detect | State | Change | Verify | Rollback |
| --- | --- | --- | --- | --- | --- | --- |
| Firewall | firewalld, UFW or an nftables ruleset service | installed binaries and unit files, in that order; an active or configured manager is the owner | unit active/enabled, `/etc/ufw/ufw.conf` `ENABLED=`, `/etc/firewalld/firewalld.conf`, `/etc/nftables.conf` | the owner's native command under `pkexec`: `ufw --force enable` + `systemctl enable --now ufw`, or `systemctl enable --now firewalld|nftables` | the same detection again | the opposite command if the state did not change; a dismissed prompt leaves everything as it was |
| Encrypted DNS | systemd-resolved behind NetworkManager | `/etc/resolv.conf` → stub, resolved active, NetworkManager active | `resolvectl status` per link (`+DNSOverTLS`, servers) and the active connection's `connection.dns-over-tls`, `ipv4/ipv6.dns`, `ignore-auto-dns` | `nmcli connection modify` on the default-route connection (strict `yes` or `opportunistic`, provider servers with their TLS names, auto DNS ignored), then `nmcli device reapply`, falling back to `connection up` | resolved reports DoT and the provider's servers on that link | the captured connection fields are written back and reapplied |
| Private Wi-Fi address | NetworkManager Wi-Fi profile | a Wi-Fi device; the active or most recently used profile | `802-11-wireless.cloned-mac-address`: `stable`, `random`, `permanent` (hardware), `preserve` (system default) | `nmcli connection modify` on that profile | read back | the previous value is written back |
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
