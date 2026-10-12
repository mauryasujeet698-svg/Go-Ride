# Guest map and authentication setup

Flutter Map displays OpenStreetMap tiles. The customer map uses OSRM-compatible routing and Nominatim-compatible search. Endpoints can be overridden with --dart-define=OSM_TILE_URL=..., --dart-define=ROUTING_URL=..., and --dart-define=GEOCODER_URL=....

Public OSM tile and Nominatim endpoints have usage policies and rate limits; they are development defaults, not a service-level guarantee for production traffic. Select an appropriate provider or host compliant services before public launch.

The estimate-route-fares Supabase Edge Function calculates the road route server-side. Guest calls return read-only estimates. Authenticated calls create short-lived customer-owned fare quotes using a service-role-only RPC; the service-role key is never shipped in the app. Quote creation is rate-limited per user.

Google OAuth must be enabled in Supabase Auth and configured with the Google OAuth client and redirect URI io.supabase.goride://login-callback/. Register the matching redirect in Supabase Auth URL configuration and configure Android signing fingerprints. Phone OTP still requires a configured SMS provider and abuse limits.

Driver matching, driver GPS ingestion, assignment, live tracking, notifications and completed-trip lifecycle still require an operational driver application or dispatch service and end-to-end tests.
