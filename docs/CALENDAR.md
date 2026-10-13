# Connected calendars

Open CEDAR's calendar from the bar, then **Calendars**. Connect up to eight
Google, Proton or Nextcloud calendars, give each a name and color, and select a day to
see its events. Dots mark days with events. The existing timer remains below
the agenda. These connections are **read-only subscriptions**, not account
sign-in or two-way sync. Use **Open calendar** to create or edit events in
the provider's website.

## Google Calendar

1. Open Google Calendar in a browser.
2. In Settings, choose your calendar, then **Integrate calendar**.
3. Copy **Secret address in iCal format**.
4. In CEDAR, choose **Google Calendar**, name it, paste the link and choose
   **Connect calendar**. Repeat for additional calendars.

Do not use the ordinary website address or an embed URL. Some organization
administrators disable secret calendar addresses. CEDAR does not require a
Google password or access to Gmail. See [Google's official instructions](https://support.google.com/calendar/answer/37648).

## Proton Calendar

1. In Proton Calendar's web app, open Settings → Calendars and select a calendar.
2. Under **Share with anyone**, choose **Create link**.
3. Choose **Full view** for titles and details, or **Limited view** for busy times.
4. In CEDAR, choose **Proton Calendar**, paste the link, and connect it.

Creating a sharing link requires a paid Proton plan. Proton does not offer
CalDAV two-way sync; CEDAR uses its supported read-only link. Provider-side
updates may be delayed. See [Proton's sharing instructions](https://proton.me/support/share-calendar-via-link)
and [its CalDAV explanation](https://proton.me/support/subscribe-to-external-calendar).

## Nextcloud

Nextcloud is self-hosted, so CEDAR accepts any HTTPS server address you give it,
including one on your home network. There are two ways to connect:

- **Share link (no password).** In Nextcloud Calendar, open the calendar's ⋯
  menu → **Share link**, then **Copy subscription link** (or the public link
  ending in `/apps/calendar/p/…`). Anyone with this link can read the calendar.
- **Private calendar (app password).** Choose **Copy private link** (an address
  containing `/remote.php/dav/calendars/<user>/<calendar>`). CEDAR then asks for
  your username and an app password. Create the app password in Nextcloud under
  Settings → Security → **Devices & sessions**; it can be revoked there at any time.
  Do not use your login password, and note that accounts with two-factor
  authentication require an app password.

CEDAR reads the calendar's `?export` ICS feed. Redirects are followed only on the
same server, so the app password is never sent elsewhere. Self-signed
certificates that the system does not trust are rejected. **Replace link** also
replaces the stored username and app password. See [Nextcloud's calendar guide](https://docs.nextcloud.com/server/latest/user_manual/en/groupware/calendar.html).

## Importing a file

For Proton Free, or to work offline, export a calendar to `.ics`, choose
**Import .ics file** in CEDAR and enter its path. Imports are local snapshots;
they do not automatically follow changes. Disconnect and import again to replace
a snapshot. **Replace link** can turn an imported calendar into a subscription.

## Refresh, offline use and privacy

- Connections are opt-in. CEDAR makes no calendar requests until a link is added
  and Local-only mode is off in Settings → Desktop → Privacy. File imports work
  with Local-only mode on. Adding a link while offline saves it for later.
- After opening the calendar, enabled subscriptions refresh every 15 minutes
  while the shell is unlocked. **Refresh** requests an immediate update.
  Opening another month reuses the feed cache; due feeds refresh automatically.
- **Hide** removes a calendar from the agenda and pauses its refreshes. **Show**
  resumes them. **Disconnect** deletes the saved link and CEDAR's event cache;
  it does not delete provider events or revoke the provider's sharing link.
- Network failures retain the last successfully read events, mark them as saved,
  and display the provider's status under Calendars. An empty agenda means no
  saved events for that day, not proof that an inaccessible calendar is empty.
- Nextcloud app passwords live in the same private file as links, are sent only
  to your Nextcloud server as HTTP Basic authentication, and are never returned
  to the UI. Disconnecting deletes them from CEDAR; revoke them in Nextcloud too.
- A sharing link is a bearer credential: anyone who possesses it can read the
  shared calendar. Paste it only into CEDAR's masked link field. Links are passed
  to the helper over stdin, never command arguments, logs or service responses.
- Links live in `$XDG_CONFIG_HOME/cedar/calendar/connections.json`; normalized
  state is returned to the UI, while original ICS feeds are cached under
  `$XDG_CACHE_HOME/cedar/calendar/`. Directories are mode 0700 and data files are
  mode 0600. These are private plaintext files, not encrypted storage. Include
  them only in backups you trust. CEDAR's shared `settings.json` contains no links.
- Only HTTPS Google/Proton subscription endpoints, and Nextcloud calendar
  addresses on the server you name, are accepted. Redirect targets are validated
  before following; files, embedded credentials, ordinary website links and (for
  Google/Proton) local-network URLs are rejected. A Nextcloud redirect must stay
  on the original server. Links are sent only to the selected
  provider. No analytics or third-party sync service is involved.
- Locking clears event details from service memory and pauses requests. The
  private disk cache remains for offline use. Nothing is published to Trailwatch
  or the lock screen by this feature.

## Calendar format support

The Python standard-library reader handles UTF-8 and folded/escaped iCalendar
text, UTC/IANA-zone/floating times, all-day exclusive end dates, multi-day events,
DURATION, DAILY/WEEKLY/MONTHLY/YEARLY recurrence, INTERVAL, COUNT, UNTIL, BYDAY
(including ordinal weekdays), BYMONTHDAY, BYMONTH, BYSETPOS, WKST, EXDATE, RDATE,
SEQUENCE revisions and moved/cancelled RECURRENCE-ID instances. Local wall times
remain stable across daylight-saving transitions.

Unsupported rules are reported explicitly rather than silently dropping events:
hourly/minutely/secondly recurrence, BYHOUR/BYMINUTE/BYSECOND, BYWEEKNO/BYYEARDAY,
EXRULE, PERIOD-valued RDATE, THISANDFUTURE edits and custom non-IANA VTIMEZONE
identifiers. No attachments, embedded HTML, scripts or alarm commands execute.
A malformed or unsupported feed retains the last good cache and shows an error.

Limits: eight calendars, 2 MiB per feed, 5,000 input events or expanded events per
calendar/range, at most 93 days per request, and bounded recurrence history/work.
The UI reports a combined result limit rather than pretending truncated data is
complete. The reader has no optional Python dependencies to install.

## Validation

```sh
python3 -m unittest discover -s tests -p test_calendar.py
python3 tests/check_calendar.py
python3 tests/check_canopy.py
```

Provider HTTP transport is mocked in automated tests. The suite exercises real
ICS parsing, recurrence exceptions, DST, permissions, redaction, offline caching,
revoked-link failures, redirect validation, connection lifecycle, and the stdin
protocol. Offscreen QML tests render populated calendars and connection controls,
select days, verify exclusive all-day ends, and check lock cleanup. These tests
do not claim a live account connection; add your own link in the panel to verify
provider access from your desktop.
