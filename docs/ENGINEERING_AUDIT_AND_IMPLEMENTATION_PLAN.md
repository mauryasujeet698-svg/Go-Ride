# Go-Ride Engineering Audit and Implementation Plan

**Prepared against:** `main` at `667cb440bc363bf191be267b8be49e14beb0259a`  
**Scope:** Ride-sharing only. This document is a read-only source audit and proposed delivery plan. No build or deployment is authorized by this document.

## Executive decision

Go-Ride is not ready for a production release. The repository contains useful Flutter domain foundations and tests, but the customer-facing app is still a prototype. The repository has no production backend, no authenticated API integration, no real driver dispatch, no durable booking service, no live fare engine, and no complete operational support workflow. A successful APK build would not close those gaps.

The recommended delivery is a **modular monolith backend with explicit API contracts**, a customer Flutter app, a separate driver Flutter app, and an admin web console. Keep the service scope limited to ride-hailing. Do not introduce microservices until load, team ownership, or deployment constraints justify the added operational burden.

## Repository snapshot and current risk

- Default branch: `main`, observed at `667cb440bc363bf191be267b8be49e14beb0259a`.
- License: Apache-2.0.
- Main application technology: Flutter/Dart.
- The current root tree includes domain entities, use cases, a RideBloc, sync/reconciliation interfaces, tests, and GitHub Actions workflows.
- The customer UI is concentrated in `lib/main.dart` (approximately 29.6 KB in the audited snapshot), rather than a feature-oriented screen/view-model structure.
- `pubspec.yaml` does not include a production HTTP client, secure storage, router, map, location, realtime or persistence implementation on `main`.
- No backend, driver application, admin application, or delivery-partner application is present in the audited `main` tree. This does not prove none exists in another repository; it means it cannot be safely treated as part of this source tree.
- PR #8 (`feature/open-map-foundation`) is open and not merged in the observed snapshot. Its description says it adds map pin selection and foreground location, but not human-readable place search, reverse geocoding, road routing or live booking. It explicitly labels fare/request behavior as demo-only.
- The PR #8 quality and Android build workflows passed on its head commit according to GitHub Actions. That proves only those workflow steps passed for that commit; it does not prove the full ride journey works.
- Both branches observed in GitHub are unprotected. README asks the owner to configure protection manually.
- `.github/workflows/build-apk.yml` triggers on pushes to `main`, pull requests targeting `main`, and manual dispatch. Any future PR targeting `main` automatically starts the Android build. This must be considered before opening a PR if builds must remain paused.

## Code-level findings

### Existing foundations worth preserving
- Domain types for ride, driver, vehicle, fare estimate, coordinates, identifiers and money.
- A state machine and version-aware event reconciliation.
- Repository/provider interfaces for rides, places, geocoding, routing, auth, realtime and sync.
- A retry policy that avoids retrying known conflict/auth/validation/reconciliation failures.
- Unit tests around state-machine, reconciliation, retry, value objects and the RideBloc.

### Important gaps and review items
1. **UI is not wired to the domain foundation.** The current main UI is a prototype and must not imply a ride was actually booked when only local state changed.
2. **No production repository implementation.** The interfaces need HTTP/API, auth, storage and realtime implementations with test doubles.
3. **Fare estimate contract is incomplete.** It has an amount and distance but lacks explicit currency, quote expiry, route/vehicle/category, fare breakdown, policy/version and server authority metadata.
4. **Ride model and transition contract need review.** `RideStateMachine` permits same-state transitions and models `cancelling` as a temporary state. Server-side validation must remain authoritative; the client state machine is not a security boundary. Explicit expiration, no-show and cancellation reasons should be specified. Driver assignment must be atomic on the server.
5. **Retry/idempotency boundary needs hardening.** Client retry alone cannot guarantee duplicate safety. The backend must persist and enforce an idempotency key, return the original result for duplicate intent, and distinguish retryable network/server failures from non-retryable responses.
6. **Sensitive values.** `Ride.toString()` redacts `startOtp`, which is good. Add automated tests for redaction and ensure OTPs, tokens, phone numbers and precise locations never enter logs or analytics.
7. **No end-to-end proof.** Existing unit tests are not a substitute for widget tests, API integration tests, dispatch concurrency tests, device tests and a complete controlled ride journey.
8. **Generated code is built in CI.** The current workflows run code generation. The Android workflow additionally runs `flutter create` and `flutter build apk --release`; do not trigger it until the user explicitly authorizes the build.
9. **Dependency versions require deliberate review.** Do not accept dependency-bot upgrades blindly; review breaking changes, generated-code compatibility and supported Flutter/Dart SDKs.
10. **No documented production operational controls.** Need environment separation, secrets management, monitoring, backup/restore proof, deployment rollback, incident runbooks, rate limits, abuse prevention and data-retention rules.

## Proposed architecture

### Client apps
- **Customer Flutter app:** onboarding/auth, map/search, quote, request, live status, trip history, safety, support, profile/privacy.
- **Driver Flutter app:** onboarding, identity/vehicle documents, verification status, online/offline, offer acceptance, pickup navigation, arrival, ride PIN, active trip, completion, earnings, support and safety.
- **Admin console:** responsive web application preferred for operational density; role-scoped tools for verification, ride monitoring, support cases, fare/zone configuration, audits and reporting.
- Keep customer, driver and admin permissions separate. Do not assume that hiding a UI action enforces authorization.

### Backend
Start with a **modular monolith**, with modules and ownership boundaries:
1. Identity and access
2. Rider/driver profiles and document verification
3. Vehicles and service eligibility
4. Places, routing and fare quotes
5. Ride lifecycle and idempotency
6. Dispatch and driver availability
7. Realtime events and snapshot recovery
8. Payments/settlement (later, behind a provider abstraction)
9. Support/safety case management
10. Admin RBAC, audit events and operational reporting

### Data and runtime proposal
- PostgreSQL as the transactional source of truth; evaluate PostGIS for proximity and geographic queries.
- Redis only for ephemeral presence/short-lived dispatch data if measurement shows it is needed; it is not the authoritative ride store.
- REST for commands and authoritative snapshots. WebSocket or managed realtime transport for versioned event delivery. On reconnect, recover from a REST snapshot and reconcile event versions.
- A transactional outbox or equivalent reliable event publication mechanism for database changes that must be broadcast.
- Provider interfaces for map rendering, place search, geocoding, routing, SMS/OTP, payments and notifications.
- Use a managed deployment approach for the first pilot, selected after cost, region, operational support, data-residency and team-maintenance comparison. Do not commit to a cloud provider before that decision.
- Keep public demo map tiles/geocoding/routing endpoints out of production traffic unless their terms and capacity explicitly permit the expected use. A map tile renderer does not provide place search, road routing or a production SLA.

### Ride lifecycle contract
Proposed server-owned states:
`REQUESTED → SEARCHING → DRIVER_ASSIGNED → DRIVER_ARRIVING → DRIVER_ARRIVED → IN_PROGRESS → COMPLETED`

Terminal/alternate states: `CANCELLED`, `EXPIRED`, `NO_DRIVER_FOUND`, and `FAILED`. Cancellation should carry an actor and reason; no-show should be explicit and policy-controlled. The exact state graph and whether payment/settlement is a separate state machine must be finalized in API contract review.

Required invariants:
- Every command is authenticated and authorized server-side.
- Fare quote has a unique ID, expiry, currency, route/distance source, vehicle category, breakdown and pricing-policy version.
- Quote and ride fare are computed/validated by the server, never trusted from a client amount.
- Create/cancel/start/complete commands are idempotent.
- Driver assignment is transactional and prevents one driver from being assigned to conflicting active rides.
- Ride state changes use a server version and conditional update/ETag; stale commands return a conflict plus a fresh snapshot.
- Ride-start PIN is verified server-side and rate-limited; never expose it in logs or analytics.
- Realtime messages carry ride ID, server version, event ID and timestamp. Gaps trigger snapshot recovery.
- Active ride is restored after app restart/background/resume from server state, not only local memory.

## API contract outline

Use versioned JSON APIs, consistent error envelopes, correlation IDs and OpenAPI documentation. Candidate endpoints:
- `POST /v1/auth/otp/request`, `POST /v1/auth/otp/verify`, `POST /v1/auth/refresh`, `POST /v1/auth/logout`
- `GET /v1/me`, `PATCH /v1/me`, `DELETE /v1/me`
- `GET /v1/places/search?q=...`, `GET /v1/places/reverse?lat=...&lng=...`
- `POST /v1/routes/quote`
- `POST /v1/fare-quotes`, `GET /v1/fare-quotes/{id}`
- `POST /v1/rides` with idempotency key, `GET /v1/rides/active`, `GET /v1/rides/{id}`
- `POST /v1/rides/{id}/cancel`, `POST /v1/rides/{id}/arrived`, `POST /v1/rides/{id}/start`, `POST /v1/rides/{id}/complete`
- `GET /v1/rides` with pagination, `POST /v1/rides/{id}/rating`
- Driver-specific routes for availability, location heartbeat, offer response, document submission and earnings; all role-scoped.
- `POST /v1/support/cases`, `GET /v1/support/cases/{id}`; admin-only case actions and audit endpoints.
- Realtime channel authentication must be short-lived and scoped to permitted rider/driver/ride subscriptions.

These are design candidates, not deployed endpoints. Final API schemas, error codes and auth semantics must be versioned before clients are wired.

## UX screen inventory and acceptance criteria

### Customer
1. Launch/session restore: loading, unauthenticated, expired session, recover active ride.
2. Phone onboarding/OTP: resend cooldown, attempt limits, offline/error feedback.
3. Home/map: current location permission rationale, denial/manual fallback, map zoom/pan, accessible controls.
4. Pickup/destination: suggestions, reverse geocoding, manual pin, clear/edit invalidation, duplicate place prevention.
5. Route preview: real route polyline, distance/ETA source, unavailable-route state.
6. Ride category: only categories serviceable in the selected zone; clear vehicle capacity and estimated pickup.
7. Quote review: itemized fare, currency, quote expiry, applicable taxes/fees and transparent caveats.
8. Request/searching: retry-safe request, cancellation policy, no-driver-found/timeout state.
9. Driver assigned: driver/vehicle identity and plate, ETA, masked contact, safety tools.
10. Driver arriving/arrived: status timestamps, pickup instructions and verified PIN flow.
11. In trip: route and live driver/ride status, trip sharing, emergency escalation path, network-loss recovery.
12. Cancellation: reason, policy/fee disclosure, race/conflict resolution.
13. Completion: final fare from server, payment/settlement status, receipt, rating/feedback.
14. Trips: loading/empty/error, pagination, details/receipt, support entry.
15. Support/safety: create case, attach permitted trip context, case ID/status, escalation expectations; never present a dead SOS button.
16. Profile/settings: language, notifications, privacy, data deletion, logout and help.

### Driver
1. Phone auth and driver terms.
2. Driver profile, KYC/documents, vehicle details, review/pending/rejected/resubmit states.
3. Availability with clear online/offline state and permissions.
4. Ride offer card: pickup/destination summary, payout/fare basis, distance, countdown, accept/reject.
5. Atomic accept/decline; expired offer is clearly shown as unavailable.
6. Pickup route, arrival, rider pickup verification/PIN.
7. In-trip status, navigation fallback, completion.
8. Cancellation/no-show with policy, reason and audit.
9. Earnings/trip history/settlement state.
10. Safety, support, account and app/network status.

### Admin
1. Secure sign-in with MFA where feasible and least-privilege role access.
2. Operational overview with freshness timestamps and service health, not fabricated live metrics.
3. Driver onboarding review with document access logging and reasoned approve/reject.
4. Ride search/monitor with server event timeline and permission-gated sensitive fields.
5. Support case queue, assignment, SLA/escalation status and internal notes.
6. Fare/service-zone/vehicle category configuration with effective dates and change audit.
7. Incident/safety workflow with restricted access and documented escalation ownership.
8. User/driver account restrictions with reason and appeal process.
9. Audit log, role management, exports with privacy safeguards.
10. Reports for booking conversion, cancellation/no-driver-found, driver supply, support resolution and service reliability.

## Maps, dispatch and launch geography

- Select launch zone(s) and validate real address/place coverage before committing to a map provider.
- Evaluate provider quality and cost for place autocomplete, reverse geocoding, route distance/ETA, navigation, map tiles, attribution, caching, rate limits, India coverage and support.
- Treat OSM data, OSM tile servers, geocoding services and routing engines as separate products with separate usage policies.
- A route must be computed from road-network routing, not straight-line distance. Display source/failure states rather than fabricated ETA or fare.
- Driver location should be sampled based on movement and active state; only send while driver is on duty/active trip with appropriate disclosure. Validate timestamps, accuracy and impossible jumps server-side.
- Dispatch initially can use eligible nearby drivers with a deterministic ranking and atomic offer assignment. Record why offers were sent/rejected/expired. Tune ranking only after reliable telemetry exists.

## Security, privacy and operations checklist

- OTP throttling by phone, device and network; resend cooldown and abuse detection.
- Short-lived access tokens, refresh rotation/revocation, secure storage and role-scoped authorization.
- TLS everywhere; secrets only in server-side secret manager; never store production credentials in GitHub code.
- Server validation for IDs, coordinates, fare, quote expiry, driver status and every state transition.
- Rate limits on auth, quote, booking, cancel, location heartbeat, search and support endpoints.
- Minimize exact-location retention; document purpose, access, retention and deletion. Never log auth tokens, OTPs or unnecessary precise coordinates.
- Encrypt sensitive document storage; restrict admin access; log access and decisions.
- No fake SOS: safety features require a tested operational escalation path, ownership, contact routing and runbook.
- Payment integration must use a compliant provider; do not store raw card data. Reconcile webhooks idempotently and model pending/failed/refunded outcomes.
- Use OWASP MASVS/MASTG as mobile security verification references.
- Define backups and test restore; service health checks, structured redacted logs, crash reporting, alert routing, on-call ownership and rollback procedure.
- Define incident response and breach handling before pilot.

## Test plan (build is intentionally not run)

### Unit tests
- Full state transition matrix and terminal states.
- Reconciliation: stale, duplicate, one-step transition, gap recovery and invalid transition.
- Quote expiry/currency/rounding and fare policy versions.
- Idempotency: same key/same payload, same key/different payload.
- Retry classification and bounded backoff.
- Permission/role decisions and privacy redaction.

### Widget tests
- All customer/driver/admin key views with loading, empty, error, offline and permission-denied states.
- All visible controls have real behavior or are disabled with an explanation.
- Light/dark contrast, large text, small screens and Hindi/English text expansion.
- Accessibility labels, touch target size and keyboard/focus behavior.

### API/integration tests
- Auth lifecycle, expired/revoked token and role boundary.
- Durable ride create/read/restart; duplicate booking; stale quote; server fare authority.
- Simultaneous accept from multiple drivers; cancellation vs assignment race; wrong PIN; duplicate completion.
- Realtime disconnect, duplicated/out-of-order events, version gap and snapshot recovery.
- Payment webhook duplicate/reordering and reconciliation (when payment is enabled).
- Support case creation, access restrictions and audit trail.

### Release/device checks
- Physical Android device tests on supported Android versions and low-end hardware.
- Poor network, airplane mode, permission revocation, background/resume, process death and app upgrade.
- Load test dispatch and location ingestion; baseline SLOs should be agreed after pilot capacity assumptions.
- Verify the APK's source commit, version, signing identity and SHA-256 after the authorized build. Do not infer release readiness from CI green alone.

## Implementation sequence

1. **Contain release automation:** keep all implementation on a non-main branch; avoid opening a PR to main because it triggers the Android build. Do not dispatch the build workflow until explicitly authorized.
2. **Close design decisions:** launch geography, vehicle categories, cash/UPI/payment phase, OTP provider, map/routing provider, hosting/region, admin web vs app and support staffing.
3. **Stabilize contracts:** formalize lifecycle, quote, auth, idempotency, error envelope, realtime versioning and OpenAPI.
4. **Build backend skeleton and tests:** migrations, health checks, auth/roles, quote/ride persistence, audit and idempotency.
5. **Wire customer app:** replace prototype-only interactions with real repositories; complete route/search/quote/request/ride lifecycle and recovery.
6. **Build driver app:** onboarding, verification, availability, dispatch, pickup PIN, active trip, completion and support.
7. **Build admin console:** verification, ride operations, support/safety cases, configuration and audits.
8. **Operational integration:** map/routing, OTP, notifications, payment/settlement as agreed, monitoring and incident runbooks.
9. **Independent review:** source review, threat model, test inventory, UI accessibility/contrast, privacy and release checklist.
10. **Quality validation:** run analysis/unit/widget/API/integration checks without the Android release workflow where feasible; document anything that cannot be verified in this environment.
11. **Explicit build gate:** only after the user authorizes it, run the Android build workflow, inspect artifacts/logs and report exact commit, workflow status, APK path/artifact retention and checksum.

## Decisions that must not be guessed

The following materially affect architecture or real-world operation and must be recorded before production wiring:
- First pilot city/zone and initial vehicle types.
- Who operates customer/driver support and emergency escalation, including hours and escalation contacts.
- OTP/SMS provider and expected cost/volume.
- Map/search/routing provider and acceptable monthly budget/terms.
- Initial hosting region/provider, database backup expectations and responsible operator.
- Whether first release is cash-only, UPI via provider, or includes other payment methods.
- Driver verification process and who approves documents.
- Whether admin is a web console (recommended) or must also be a mobile app.
- Exact treatment of the existing delivery-partner app. No delivery-partner code is visible in this repository's audited main tree; do not silently fold delivery into Go-Ride ridesharing.

## Final gate

This plan is not a claim that implementation is complete. A build-ready implementation must have actual code, passing quality tests, no fake production behavior, configured required services and documented remaining limitations. The build workflow must remain untriggered until explicit authorization.
