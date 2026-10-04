# Privacy and external access

CEDAR contains no analytics, advertising, installation IDs, automatic crash upload or cloud account requirement. Local CPU, audio, device and window information is used locally to render the requested interface. This does not control unrelated applications' tracking.

Local-only is the distribution default. Weather, IP location and remote media artwork require separate explicit settings; existing manual coordinates alone do not authorize a network request. Python weather helpers enforce the same policy before opening a connection. Images from media, menus, tray and theme previews pass through the shared local/remote source policy. Shared text controls use plain text, preventing markup-driven image loads. Local-only mode is a policy for first-party CEDAR code, not an operating-system sandbox for arbitrary QML or user commands.

External destinations, payloads, frequency and retention are authoritative in `data/dependencies.json` → `remoteServices`. IP location contacts IPWhois and caches approximate coordinates privately; forecast and city search contact Open-Meteo. A server necessarily sees connection metadata such as the public IP. Remote artwork can contact the host named by a media player. Package operations contact the user's configured package repositories. Update checks are manual; this candidate accepts locally downloaded, signed archives only.

Clipboard history and window-title Trails remain off by default, bounded, and cleared on lock. Existing clear actions remain. Credentials/passwords are never copied into distribution manifests. Local authentication responses remain in the PAM flow. Persistent retention controls across all activity/history types are not yet a uniform plugin interface; this is a release gate, not a promised sandbox.

Logs are local. Service-log excerpts are bounded to 60 lines and redact common credentials, home paths, addresses, device addresses, email and hostname. Redaction cannot recognize every arbitrary secret; inspect a diagnostic preview before sharing. Nothing uploads diagnostics automatically. Distribution journals are private and contain only recorded transaction paths, hashes, ownership, package results and recovery facts—not environment dumps.

Evidence: offline policy tests deny requests before transport; QML image source policy is tested with synthetic URLs. Process-level outbound traffic capture on a native isolated desktop remains Not Tested. No claim of measured network silence is made until that test runs.
