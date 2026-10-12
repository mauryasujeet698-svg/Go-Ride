# Guest map and authentication setup

This build uses Flutter Map with OpenStreetMap tiles, OSRM-compatible routing and Nominatim-compatible address search. Endpoint values can be overridden with --dart-define=OSM_TILE_URL=..., --dart-define=ROUTING_URL=..., and --dart-define=GEOCODER_URL=....

Public OSM tile and Nominatim endpoints have usage policies and rate limits; they are development defaults, not a service-level guarantee for production traffic. Before public launch, select appropriate providers or host compliant services, configure quotas and monitoring, and set the endpoint defines.

Guest fare estimates are read-only, do not create a ride quote, and are calculated from configured database pricing rules using road distance returned by routing. When the user signs in, the authenticated booking screen requests a fresh quote before the user can confirm a real ride.

Google OAuth must be enabled in Supabase Auth and configured with the correct Google OAuth client, redirect URL and Android app signing fingerprints. The app redirect URI is io.supabase.goride://login-callback/; register the matching redirect in Supabase Auth URL configuration. Phone OTP still requires a configured SMS provider and abuse limits.

Driver matching, driver GPS ingestion, assignment, live tracking, notifications and completed-trip lifecycle are not considered complete merely because the customer UI is present. They require an operational driver application or dispatch service and end-to-end tests.
