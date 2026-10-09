# Go-Ride

Go-Ride is a ride-hailing platform planned as three separate apps: Customer, Driver Partner and Admin, backed by a shared API and database. It is ride-hailing only. Mature ride platforms are product-quality benchmarks; Go-Ride has its own implementation and identity.

## Current engineering status

**Status: engineering work in progress; not production-ready.** The customer app remains a prototype, while this engineering branch adds initial separate Driver Partner/Admin shells and a backend foundation. These are not complete operational apps.

Implemented foundations include ride-domain models, state-machine/reconciliation contracts, application use cases, a RideBloc, provider interfaces, unit tests, and GitHub Actions quality/build workflows.

The current customer UI still contains prototype-only behaviour. Fare estimates are not yet connected to the new server quote endpoint, booking state is not persisted by a live backend, and the app does not yet integrate the identity provider, live map/GPS/routing provider or driver matching service. A successful APK build is not proof of a complete ride journey. The Driver Partner and Admin shells now include an explicit backend-readiness check, but this is diagnostic only and does not enable authenticated operations.

## Architecture principles

- The backend will be authoritative for fare quotations and ride state.
- REST snapshots are the recovery source of truth; realtime events are reconciled against server versions.
- Map rendering, place search, geocoding, routing, authentication, persistence and realtime transport must sit behind replaceable interfaces.
- Customer, Driver Partner and Admin are separate apps backed by one shared API/data model.
- Payment methods and other provider-dependent capabilities remain disabled until the server integration and operational prerequisites are verified.
- Keep a modular architecture. Do not introduce microservices without a concrete need.
- Never commit API keys, credentials, signing keys or production secrets.

## Development

Prerequisites: a current stable Flutter SDK and Dart version compatible with pubspec.yaml.

    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter analyze
    flutter test
    flutter build apk --release

Generated Freezed files are generated during CI and are intentionally not committed.

## GitHub workflow

- Go-Ride Engineering Checks runs backend typecheck/tests, Customer analyze/tests, and Driver Partner/Admin analyze/tests plus Android debug-build smoke tests on engineering branches. These checks do not create release APKs.
- Go-Ride Quality Gate runs dependency installation, code generation, static analysis and tests on pull requests targeting main and pushes to main.
- Go-Ride Android Build builds a release APK for pull requests and pushes to main, and can be started manually from Actions.
- Build artifacts include the source commit and APK checksum metadata. Artifacts are temporary; download and archive a release you intend to keep.
- Keep workflow token permissions minimal and review workflow changes like application code.
- Protect main in GitHub repository settings: require pull requests, require the Quality Gate check, and disallow force pushes/deletions. If GitHub settings cannot be configured by automation, the repository owner must enable these controls manually.

## Delivery roadmap

See docs/ROADMAP.md, docs/THREE_APP_FEATURE_FLAGS_AND_PAYMENTS.md and backend/README.md for the current plan and explicit implementation limitations.

## Definition of done

A feature is complete only when its behaviour is implemented and relevant tests pass. Screens, local demo state and successful compilation do not count as completed backend functionality. Production readiness requires deployed/configured services and end-to-end ride journey validation.
