# Go-Ride delivery roadmap

This is the delivery order for the customer Android app and its shared platform. Driver and admin apps remain separate future clients.

## Phase 0 — Repository and engineering baseline

- [x] Flutter/Dart domain and application foundation exists.
- [x] GitHub Actions quality gate and Android release build exist.
- [x] Bring the reviewed Batch 2 foundation onto main.
- [ ] Enable required PR review/status checks and prevent force-push/deletion on main.
- [ ] Add/verify dependency and secret scanning settings in GitHub.
- [ ] Complete a source-by-source architecture and security review.

Acceptance: main is the authoritative integration branch; every proposed change has passing analysis/tests and the Android build; release artifacts identify the exact source commit and checksum.

## Phase 1 — Customer UI and app lifecycle

- [ ] Polish home, pickup/destination entry, vehicle selection and booking review.
- [ ] Implement explicit loading, empty, error, offline and permission-denied states.
- [ ] Make trips/profile/support screens honest and useful; remove dead or misleading controls.
- [ ] Verify theme contrast, accessibility, Hindi/English foundations and small-screen layouts.

Acceptance: all visible controls have defined behaviour and UI tests cover the primary customer navigation.

## Phase 2 — Maps, places and navigation

- [x] Add a Flutter map renderer (`flutter_map`) with OpenStreetMap attribution and a replaceable tile URL.
- [x] Add foreground GPS/current-location permission handling and manual pickup/destination pin selection.
- [x] Store selected pin coordinates in the booking draft and clear stale coordinates if a rider manually edits the corresponding text.
- [x] Document that public OSM community endpoints are not unlimited production infrastructure.
- [ ] Implement real place search/autocomplete and reverse geocoding through a compliant provider.
- [ ] Implement road routing, route polyline, road distance and ETA from a real routing provider.
- [ ] Evaluate turn-by-turn text/voice guidance, off-route detection and rerouting.
- [ ] Choose and load-test a launch-appropriate tile/geocoding/routing provider or a self-hosted deployment.

Partial acceptance met: interactive map pan/zoom, map-pin selection and foreground location permission/error handling have been added to the app. The full phase remains open until location search, real routes/distance/ETA, provider capacity, and launch-region coverage are implemented and verified.

## Phase 3 — Shared backend and data contracts

- [ ] Select and document a maintainable backend/database deployment approach.
- [ ] Define authenticated API contracts and persistent rider/booking/quote records.
- [ ] Implement server-authoritative fare quotes and ride state transitions.
- [ ] Add idempotent booking intent, race-safe cancellation, audit events and authorization.
- [ ] Define driver matching and telemetry contracts for the future driver app.
- [ ] Add realtime delivery plus REST snapshot recovery and reconnect behaviour.

Acceptance: integration tests prove durable bookings, duplicate-request safety, fare authority, valid transitions and recovery after timeouts/reconnects.

## Phase 4 — Complete ride journey

- [ ] Connect the customer app to the real backend.
- [ ] Add driver assignment and real driver location when driver-side service exists.
- [ ] Verify server-side ride-start PIN, cancellation and completion.
- [ ] Restore active ride state after app restart/background/resume.
- [ ] Add trip history, receipt, rating and feedback persistence.

Acceptance: end-to-end test completes booking through ride completion against a real backend or controlled integration environment; simulations are clearly labelled.

## Phase 5 — Support, safety and payments

- [ ] Implement customer support request lifecycle and operational ownership.
- [ ] Define SOS, emergency contact and trip-sharing workflows with appropriate privacy controls.
- [ ] Implement cash settlement records where applicable.
- [ ] Integrate UPI/payment provider only after backend reconciliation and refund/failure flows are designed.

Acceptance: support/safety/payment workflows have verified server-side records, permission checks, failure handling and operational runbooks.

## Phase 6 — Production hardening and release

- [ ] Test duplicate requests, cancellation races, incorrect PINs, stale events, reconnects and network loss.
- [ ] Review privacy, data retention, authentication, rate limits and logging for sensitive data.
- [ ] Verify crash/error monitoring, backups, deployment rollback and service health checks.
- [ ] Test on physical Android devices and launch-area map coverage.
- [ ] Archive a versioned APK with source commit and SHA-256 checksum.

Acceptance: no unresolved release-blocking security or correctness findings; deployed dependencies are configured; real ride journeys pass; limitations are documented.

## Non-negotiable

A green CI run proves only the checks that ran. An APK proves only that the app built. Neither by itself proves a production ride-hailing service works.
