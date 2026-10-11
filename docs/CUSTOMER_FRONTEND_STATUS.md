# Customer frontend completion notes

## Scope of this phase

This branch prepares the Go-Ride customer Android frontend only. It does not deploy a backend, enable live ride booking, contact drivers, store real trip history, or activate payments.

## Map and location capabilities

- Interactive OpenStreetMap map preview and full-screen pickup/destination pin picker.
- Foreground GPS selection with permission and failure handling.
- Search for Indian addresses and landmarks and reverse-geocode a manually selected pin.
- Road route polyline, road distance, and approximate driving duration when the routing service responds.
- Location names and coordinates are kept in the local booking draft only.

## External provider limitations

The current adapter uses the public Nominatim service for low-volume place search/reverse geocoding and the OSRM demo routing service for route previews. These are not production service guarantees. They can be rate-limited, unavailable, or unsuitable for commercial traffic. Do not ship public traffic against these endpoints without checking their current usage policies and selecting an appropriate hosted or self-hosted provider. Map tiles also need a compliant, launch-capable provider and visible attribution.

Provider calls are isolated in `lib/infrastructure/maps/open_map_providers.dart` so a provider can be replaced without changing the booking UI. No API key or credential is required or embedded for this development adapter.

## Demo-only behaviours

- The displayed fare is illustrative and not calculated from the route.
- The preview request is local-only; it does not contact a driver or create a durable booking.
- Notifications, saved places, account security, support submissions, and trip history are not connected to persistent services.
- The backend readiness card is diagnostic only; a configured URL is not proof that booking capabilities are available.

## Before backend setup

Run dependency installation, code generation, `flutter analyze`, `flutter test`, and an Android release build. Review the generated artifact on a physical Android device, especially map permissions, search failures, map tile availability, route rendering, and small-screen layouts. Archive the APK together with its source commit and SHA-256 metadata only after CI and device verification.
