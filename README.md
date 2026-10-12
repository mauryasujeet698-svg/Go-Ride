# Go Ride

Go Ride is a Flutter ride-sharing application currently based on the existing MOTIS ride-sharing codebase. This repository rebrand changes the customer-facing product name while intentionally retaining the current backend endpoints, authentication redirect scheme, Android application ID, and Firebase registration. Those identities must not be changed until the backend and Firebase configuration are deliberately migrated.

## Current status

- Existing Supabase authentication/data access and Firebase Cloud Messaging configuration are retained.
- The Android application ID remains `com.motis.mitfahr_app` so the existing Firebase Android registration continues to match.
- CI builds split-per-ABI Android APKs and enforces a **25 MiB maximum per APK**. CI artifacts are debug-signed test builds, not Play Store production releases.
- The backend has **not** been production-security certified. Review of `supabase/database.sql` found 11 `SECURITY DEFINER` functions without an explicit function-level `SET search_path`, plus broad public-read policies on selected tables. These need a function-by-function access review before a production launch. No live backend configuration or data is changed by this repository work.

## Requirements

- Flutter stable (CI currently pins Flutter 3.29.3)
- Java 17 for Android builds
- Android SDK installed for local APK builds

## Local setup

1. Clone the repository.
2. Create a local `.env` from `example.env` and supply the existing Supabase URL and public anon key. Never put a service-role key or other privileged credential in the client app.
3. Run `flutter pub get`.
4. Run `flutter gen-l10n` if generated localization files need refreshing.
5. Run `flutter run` on a device or emulator.

## Checks

```bash
dart format --output=none --set-exit-if-changed --line-length=120 $(find lib test -name "*.dart" -not -name "*.mocks.dart")
flutter analyze
flutter test --coverage
```

CI creates `.env` from the GitHub Actions secret without printing its value, runs formatting, analysis and translation checks, builds optimized split APKs, verifies each APK against the size limit, uploads artifacts, then runs tests and coverage.

## Security and deployment boundary

This repository may contain configuration files and a database schema dump, but committing a change does not update a hosted Supabase or Firebase project. Database policy/function fixes, authentication settings, redirect URLs, production credentials, and backend deployments are intentionally deferred until the backend audit is completed and explicitly approved.