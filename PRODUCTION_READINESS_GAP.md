# Go-Ride customer app: readiness status

This branch replaces the previous customer UI with a Go-Ride-branded Flutter app connected to the Go-Ride Supabase schema.

## Included in this build
- Phone OTP sign-in using Supabase Auth.
- Current-location pickup using foreground location permission.
- Address geocoding through the device geocoder.
- Server-side fare estimates using `estimate_fares`.
- Idempotency-key ride creation and server-side cancellation RPCs.
- Active-ride restoration and ride-event subscriptions.
- Row-level security and least-privilege database grants are enforced by Supabase migrations.
- CI runs formatting, analysis, tests, ABI-split release APK builds, and checks every APK against the 25 MiB limit.

## Not yet production-ready
- SMS delivery must be configured and tested in Supabase Auth with the selected SMS provider and abuse limits.
- Driver app, driver onboarding/verification, dispatch/matching, driver GPS ingestion, ride OTP verification and completed-ride lifecycle still need to be built.
- Real map UI, route distance/ETA, geocoding reliability, push notifications, support/SOS, payments, privacy/legal disclosures and account deletion need end-to-end implementation.
- Test on physical Android devices, test RLS using multiple customer accounts, run booking concurrency/load tests, and review all security advisor findings before launch.
- CI APKs are debug-key signed for install/testing only. Google Play needs a separately controlled upload keystore and signed AAB.

## Security
Only the Supabase publishable key is compiled into the client. Never add a service-role key, database password, SMS provider secret or signing key to this repository or APK. Public clients are not trusted; authorization is enforced by database grants and RLS.
