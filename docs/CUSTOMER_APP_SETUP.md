# Go-Ride customer app setup

## API connection status

The customer home screen can check the shared API readiness endpoint. Configure the API origin at build time; no backend URL or secret is hard-coded in the app.

Local development example:

```bash
flutter run --dart-define=GO_RIDE_API_BASE_URL=http://10.0.2.2:3000
```

For a physical Android phone, use the development machine's LAN IP address instead of `10.0.2.2`, and ensure the API is reachable from that device. Do not expose a development API to the public internet.

For an APK build:

```bash
flutter build apk --debug --target-platform android-arm64 \
  --dart-define=GO_RIDE_API_BASE_URL=https://YOUR-API-HOST
```

Replace the placeholder with the deployed API origin. Never put JWT signing keys, database credentials, pickup-PIN secrets, or payment credentials in `--dart-define` or the mobile app.

The app calls `GET /health/ready` only when the rider taps **Check** on the backend connection card. A healthy response only means the API reports its dependencies ready; it does **not** prove that a rider is authenticated, dispatch is enabled, a verified driver is online, or a ride can be booked.

## Current customer app limitations

- Map pin selection and foreground current-location selection are available in the map picker.
- Human-readable place search and reverse geocoding are not yet connected.
- Road route, polyline, distance and ETA are not yet wired into the customer journey.
- Fare display and request flow remain explicitly demo-only until authenticated quote and ride APIs are integrated.
- The backend readiness client is intentionally unauthenticated and only calls health/capabilities endpoints. Do not use it for protected ride commands.

## Verification

Run the customer checks from the repository root:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```
