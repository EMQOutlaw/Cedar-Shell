# CEDAR Trailwatch

Trailwatch replaces the small clock in CEDAR's real `WlSessionLockSurface`.
The opaque lock surface, PAM service, authentication controller, idle locking,
and suspend-after-secure behavior stay in `modules/LockScreen.qml`.
`modules/TrailwatchView.qml` owns presentation and forwards responses to that
controller. The preview never requests a session lock or calls PAM.

## Preview and configuration

Run from the source directory:

```sh
qs -p trailwatch-preview.qml
```

This opens a normal, resizable window using available services. Its heading
explicitly says **PREVIEW / NOT LOCKED**. Close it like any other window.
For a test without system connections, use `python3 tests/check_trailwatch.py`.
To retain the rendered test fixtures, supply a screenshot directory as its
argument. Fixture screenshots are illustrative, not readings from your machine.

The registered CEDAR source uses Trailwatch on its next lock. No replacement
PAM policy, system service installation, or desktop lock is needed to preview.
Use **Settings → Power & Lock** for these persistent preferences:

| Setting | Default | Behavior |
| --- | --- | --- |
| `lockPrivacy` | `true` | Hides media, agenda, reminder and peripheral names |
| `lockMediaDetails` | `false` | Allows track/artist text when privacy is off |
| `lockAgendaDetails` | `false` | Allows calendar/reminder/timer labels when privacy is off |
| `lockMediaControls` | `true` | Allows playback and volume adjustment while locked |

## Fingerprint

When `/etc/pam.d/omarchy-lock-fingerprint` exists and `fprintd-list` reports an
enrolled print, the access terminal shows a small fingerprint indicator and the
reader's prompt. A second PAM conversation on that service starts as soon as
the compositor lock is secure, retries after each failed verification, and is
aborted the moment the session unlocks by any means. The password field keeps
working throughout; neither path can unlock without PAM success. Nothing is
enrolled or changed by CEDAR; `scripts/fingerprint.py` only reads availability.

The **Shield** button hides details for the remainder of the lock session,
on every display. It cannot reveal information forbidden by preferences.
Notification bodies, album art, SSIDs and VPN names are never drawn. A visible
calendar time still reveals that an event exists; privacy replaces its title.
Theme Reduced Motion disables the breathing indicator, the seconds cursor and
the entrance (lantern bloom, filament and staggered instruments settle in over
about a second otherwise), while time and the solar position continue to
update once a minute. The lock surface is opaque from its first frame; the
entrance only reveals content, it never uncovers the desktop.

Password fields mask immediately, preserve PAM's visible-response behavior for
interactive challenges, clear on submission and controller reset, and regain
focus after authentication completes. Enter submits, Escape and Ctrl+U clear,
and Tab navigates controls. Caps Lock uses the existing Linux LED monitor and
says **CAPS UNKNOWN** if the device does not expose it. No credentials are logged.

## Instruments and sources

| Instrument | Source and fallback |
| --- | --- |
| Sky Watch | Existing Open-Meteo weather using saved coordinates or automatic approximate IP location; current temperature, feels-like, wind and this hour's precipitation probability. Failed or >30-minute-old data is marked stale. Location detection and city override are described in WEATHER.md. |
| Trail Board | Optional local agenda feed, actual Omarchy systemd reminders, and CEDAR Core's existing timer. Unconnected, empty, stale and unavailable states are distinct. |
| Signal Beacon | Existing NetworkManager snapshot, including its reported internet connectivity, active VPN/WireGuard and BlueZ device count. An active link alone does not claim internet access. |
| Camp Power | UPower battery and charging state; power-profile service; reported BlueZ peripheral battery percentages. Missing power data does not imply AC power. |
| On the Air | Existing native MPRIS playback and PipeWire output/volume; capability-gated previous/play/pause/next and volume buttons. No active player has an empty state. |
| Watchtower | Existing CPU, RAM, monitored filesystem and hottest valid temperature sensor. Failed system/user service counts are read from systemd. GPU load is shown only for active DRM devices exposing `gpu_busy_percent`. The most recent still-retained Core update result is shown, otherwise **Not checked**. |
| Forest State | Warnings → Ember; recording/privacy indicators → Watch; DND → Quiet; performance profile → Hunt; media/timer → Flow; awaiting telemetry → Awake; otherwise the locked session rests. No separate Ritual provider exists yet. |

Moon phase, external alarm accounts and phone identity are not fabricated.
GPU polling does not run `nvidia-smi` or wake a suspended discrete adapter.
There is no package-manager refresh from the lockscreen. Systemd query failures
are reported as unavailable, never zero failures.

Readiness uses a deterministic priority: battery ≤20% while discharging,
configured temperature/disk thresholds or failed services, fresh forecast
thunderstorms, disconnected network, awaiting system/network readings, DND,
then Ready. **WEATHER WATCH** is a forecast condition, not an official weather
alert. **READY** means no monitored threshold is exceeded; it is not a security
or complete hardware-health guarantee.

The extra read-only helper is shared across displays and runs every 30 seconds
only while Trailwatch is visible. Its subprocesses have three-second timeouts;
its results expire after 90 seconds. Existing system services retain their own
sampling schedules. Contours render on resize; the seconds dial repaints at
1 Hz and at 1/minute in Reduced Motion. No frame-rate polling or video runs.

## Solar path

The outer arc runs from civil dawn through sunrise, solar noon and sunset to
civil dusk. Amber covers sunrise–sunset; teal covers civil twilight. Its white
marker is the current position during that interval. At night, the face gives
the next calculated sunrise. Polar dates without crossings have an explicit
empty state. With no configured coordinates the arc stays unpopulated.

These are approximate, calculated light times in the **computer's local time**,
using the configured latitude and longitude, not a compass or GPS measurement.
The calculation selects the location’s mean-solar date, including across the date
line; displayed timestamps still use the computer’s timezone.
The implementation follows the [NOAA fractional-year solar equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF),
with 90.833° zenith for rise/set and 96° for civil twilight. Terrain and local
horizon obstructions are not modeled. Weather fields follow the
[Open-Meteo forecast API](https://open-meteo.com/en/docs).

Morning emphasizes first light; evening emphasizes last light and an additional
future event after midnight if there is one. The nearest upcoming event is
always retained. Solar labels fit the larger dial; narrow screens retain the
sunrise/sunset and first/last-light times in Sky Watch.

## Optional local calendar feed

A calendar integration may atomically publish
`$XDG_CONFIG_HOME/cedar/trailwatch-agenda.json` (default
`~/.config/cedar/trailwatch-agenda.json`). Trailwatch only reads this file;
it does not connect to an account or run publisher commands.

```json
{
  "updatedAt": "2026-10-04T08:00:00-04:00",
  "events": [
    {"start": "2026-10-04T10:30:00-04:00", "title": "Trail planning"}
  ]
}
```

Publish fresh timestamps, with explicit UTC offsets. Maximum file size is
64 KiB; at most 100 entries are read. Past entries and timezone-ambiguous starts
are excluded; feeds older than 24 hours show **stale**. The sample above is a
schema example, not an installed event. Default privacy hides titles.

## Validation

```sh
python3 -m unittest discover -s tests -v
python3 tests/check_lock_auth.py
python3 tests/check_lock_wiring.py
python3 tests/check_trailwatch.py /tmp/cedar-trailwatch-previews
python3 tests/check_desktop_ui.py
```

The Trailwatch harness renders desktop (1920×1080), ultrawide (3440×1440), laptop
(1366×768), stacked (800×900), and narrow (480×800) layouts. It checks onscreen
password geometry, privacy opt-ins and Shield, secret clearing, busy/focus state,
keyboard interaction, solar ordering/polar fallback, readiness priority and
unavailable sources. Source tests distinguish unavailable services from empty
results and reject stale/malformed calendar data.

These are offscreen checks. They do not prove physical multi-monitor focus,
real PAM authentication, actual system-bus hardware behavior or measured GPU
power consumption. Use CEDAR's existing **Test authentication** button in the
local desktop before manually validating a real lock/unlock cycle.

### Authentication wiring regression

The live session-lock surface is an implicit QML component. Its original
`auth: auth` binding shadowed the outer controller ID, leaving the terminal
without a controller. It is now bound explicitly to `authController`, with bound
component behavior. The wiring regression check reproduces the old failure and
exercises the production composition with two dynamically created surfaces and
fake PAM/Wayland boundaries: submission, failure, retry, shared field clearing
and success-only unlocking. It never takes a real session lock.

To verify your actual password in a non-locking window on the desktop:

```sh
qs -c cedar ipc call lock testAuthentication
```

This opens the existing **Test authentication** window and is ignored while
locked. Enter credentials only into that local window. A successful test reports
that the password works; closing the window does not affect the session lock.
