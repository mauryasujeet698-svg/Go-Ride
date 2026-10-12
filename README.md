# Go-Ride

Go-Ride is a Flutter customer ride-booking app with Supabase-backed authentication, fare quotes, ride requests and ride status.

## Current implementation
- Phone OTP sign-in through Supabase Auth.
- Foreground pickup location and device address geocoding.
- Server-side fare estimation and ride creation/cancellation RPCs.
- Active ride restoration and real-time ride event updates.
- Supabase row-level security and least-privilege database grants.
- GitHub Actions runs Flutter analysis/tests and creates ABI-split Android test APKs, enforcing a maximum of 25 MiB per APK.

## Run locally
Install Flutter stable (3.29.3 or compatible), then run:

```sh
flutter pub get
flutter run
```

The default client configuration points to the Go-Ride Supabase project and uses its **publishable** key. A publishable key is not a secret or access-control mechanism; never put service-role keys, database passwords, SMS-provider secrets or signing keys in the client or public repository.

## Current limitations
This is a customer MVP under test, not a complete ride-hailing production system. SMS provider configuration, driver onboarding and app, dispatch/matching, driver location tracking, map/route UI, pickup OTP, push notifications, support/SOS, payments, account deletion, privacy/legal review and load testing remain before public launch. The CI APK is signed with a debug key for testing only; Play Store distribution requires a controlled release keystore and signed AAB.

See [PRODUCTION_READINESS_GAP.md](PRODUCTION_READINESS_GAP.md) for the current launch checklist.
