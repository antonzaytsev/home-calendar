# Home Calendar

A wall calendar display that shows events from an iCloud webcal feed, with Russian localization.

## What it is

- `webcal_fetcher.rb` polls the webcal URL (with ETag / If-Modified-Since), parses the
  ICS feed and atomically writes `webcal_events.json`. A failed fetch never replaces
  good data.
- `app.rb` is a Sinatra app on Puma. It expands recurring events (RRULE, EXDATE,
  RECURRENCE-ID overrides) with `ice_cube` and serves them as JSON per day.
- The page (`views/calendar.erb`, `public/calendar.js`, `public/calendar.css`) shows a
  multi-day view that always starts one day before the selected date. The server pushes
  updates over Server-Sent Events (`/updates`), so new events appear within seconds of
  being fetched. The page also refreshes every few minutes as a fallback, and warns
  in the footer when the server is unreachable or the feed is stale.

Endpoints: `/` (page), `/events?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD`, `/updates`
(SSE), `/health` (returns 503 when data is missing or stale).

## How to start it

1. Set your iCloud webcal URL in a `.env` file:
   ```
   WEBCAL_URL=your_ical_url_here
   ```
   Optional settings: `TZ` (default `Europe/Moscow`, the zone used to place events on days)
   and `FETCH_INTERVAL_SECONDS` (default `60`).

2. Start with Docker:
   ```bash
   docker compose up -d --build
   ```

3. Open http://localhost:9000 in your browser

4. To stop:
   ```bash
   docker compose down
   ```

Rebuild the image (`--build`) after changing `Gemfile`/`Gemfile.lock`; Ruby code is
mounted into the containers, so code changes only need `docker compose restart`.

## Android tablet app

For a full-screen APK without browser tabs or an address bar, see
[android/README.md](android/README.md). Build with `bash android/build.sh`;
the installable APK is saved to `.work/android/home-calendar.apk`.
