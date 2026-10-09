# Go-Ride

Go-Ride is an original Flutter/Dart ride-hailing customer app being developed toward a production-grade service. Mature ride platforms are product-quality benchmarks; Go-Ride has its own implementation and identity.

## Current engineering status

**Status: foundation and customer UI scaffold; not production-ready.**

Implemented foundations include ride-domain models, state-machine/reconciliation contracts, application use cases, a RideBloc, provider interfaces, unit tests, and GitHub Actions quality/build workflows.

The current customer UI still contains prototype-only behaviour. Fare estimates are not route-based, booking state is not persisted by a live backend, and the app does not yet integrate a real map/GPS/routing provider or driver matching service. A successful APK build is not proof of a complete ride journey.

## Architecture principles

- The backend will be authoritative for fare quotations and ride state.
- REST snapshots are the recovery source of truth; realtime events are reconciled against server versions.
- Map rendering, place search, geocoding, routing, authentication, persistence and realtime transport must sit behind replaceable interfaces.
- The customer app is first; the shared API/data model must support separate driver and admin apps later.
- Keep a modular architecture. Do not introduce microservices without a concrete need.
- Never commit API keys, credentials, signing keys or production secrets.

## Development

Prerequisites: a current stable Flutter SDK and Dart version compatible with pubspec.yaml, plus Python 3 for the Android permission helper.

For a local Android build (the Android platform directory is generated rather than committed):

    flutter create --platforms=android --org com.goride .
    python3 tool/configure_android_location_permissions.py
    flutter pub get
    dart run build_runner build --delete-conflicting-outputs
    flutter analyze
    flutter test
    flutter build apk --release

To use a different compatible tile provider without editing Dart code, pass its documented tile URL template at build time:

    flutter build apk --release --dart-define=GO_RIDE_OSM_TILE_URL=https://your-approved-provider/{z}/{x}/{y}.png

### Open map and current location

The customer home screen now includes an interactive `flutter_map` preview and a map picker. Riders can pan/zoom, select pickup and destination pins, or request the device's current foreground location. Selected pins are stored as coordinates in the booking draft. The app currently displays coordinates as labels; human-readable place search/reverse geocoding and road routing are not implemented yet.

The default OpenStreetMap standard tile endpoint is suitable only for development and careful low-volume use. OpenStreetMap data is openly licensed, but the community tile, geocoding, and routing endpoints are separate services with their own limits and no production capacity guarantee. Before public launch, choose a compliant hosted OpenStreetMap-derived provider or plan and test a self-hosted deployment. Keep visible attribution and follow the selected provider's caching and identification rules. See the [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/) and [Nominatim policy](https://operations.osmfoundation.org/policies/nominatim/).

The app's fare display and ride-request flow remain explicitly marked as demo-only until connected to the backend and driver/dispatch system.

Generated Freezed files are generated during CI and are intentionally not committed.

## GitHub workflow

- Go-Ride Quality Gate runs dependency installation, code generation, static analysis and tests on pull requests targeting main and pushes to main.
- Go-Ride Android Build builds a release APK for pull requests and pushes to main, and can be started manually from Actions.
- Build artifacts include the source commit and APK checksum metadata. Artifacts are temporary; download and archive a release you intend to keep.
- Keep workflow token permissions minimal and review workflow changes like application code.
- Protect main in GitHub repository settings: require pull requests, require the Quality Gate check, and disallow force pushes/deletions. If GitHub settings cannot be configured by automation, the repository owner must enable these controls manually.

## Delivery roadmap

See docs/ROADMAP.md for the phased plan and acceptance criteria.

## Definition of done

A feature is complete only when its behaviour is implemented and relevant tests pass. Screens, local demo state and successful compilation do not count as completed backend functionality. Production readiness requires deployed/configured services and end-to-end ride journey validation.
