# Weather location

CEDAR starts in local-only mode with weather, remote artwork, and automatic location lookup disabled. To use weather, first allow external access and enable weather in Settings → Desktop → Weather location. Automatic location requires a separate opt-in; it estimates a city from the public IP when no manual location is saved. It does not request GPS, scan Wi-Fi networks, or need an account/API key. Existing latitude/longitude preferences continue to override detection. Select **Use automatic location** to clear that override, **Detect again** to refresh, or search for a city/postal code and select a result. Re-enabling local-only mode blocks new weather, city-search, and location requests.

IP-based locations are approximate. A VPN, proxy, mobile network, or an ISP's routing location can produce a different city. For consistent local weather while using a VPN, choose your city once. The detected or saved place is displayed in Settings, Field Station, and Sky Watch. Coordinates remain available for advanced manual overrides.

The automatic lookup uses HTTPS to IPWhois's `ipwho.is` endpoint. The provider receives the connection's public IP. CEDAR requests only city/region/country/coordinates and success status, discards other fields, and stores no IP address or network identifiers. The approximate coordinates and city are cached privately under `$XDG_CACHE_HOME/cedar/weather-location.json` (default `~/.cache/cedar/weather-location.json`). Only two decimal places of coordinates are retained. Successful results last 24 hours; a shared half-hour timer checks the cache and retries failures. Explicit detection is limited to once per minute. Failed lookups retain the last known location and label it accordingly; no location is invented.

City search sends the entered query to Open-Meteo's geocoding service and attributes GeoNames. Forecast requests continue using the existing Open-Meteo backend. No extra packages are needed. Disabling automatic location stops new automatic requests; a request already in flight may finish but cannot replace a selected manual location. Cached data remains local until normally cleared.

Provider references:
- https://ipwhois.io/documentation
- https://ipwhois.io/terms
- https://open-meteo.com/en/docs/geocoding-api

Provider availability, terms and quotas can change. This optional feature handles errors and rate limits without preventing the desktop from starting. Open-Meteo's existing non-commercial endpoint remains subject to its own usage terms.
