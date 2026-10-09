# Go-Ride shared backend

This is the shared TypeScript/Fastify API foundation for the **Customer, Driver Partner and Admin** ride-hailing apps. It is under active engineering and is **not production-ready**. Do not enable live payments or expose it publicly until the release gates below are completed.

## Implemented API surface

| Endpoint | Purpose | Important behavior |
| --- | --- | --- |
| `GET /health/live` | Process liveness | Does not prove dependencies are ready |
| `GET /health/ready` | Service readiness | Returns 503 if the database or authentication is missing, or an enabled routing/dispatch dependency is not configured |
| `GET /v1/capabilities` | App presentation hints | Flags are not authorization; server routes enforce their own checks |
| `GET /v1/me` | Resolve authenticated account | Requires a valid configured OIDC/JWT verifier and an active provisioned account |
| `POST /v1/fare-quotes` | Create a server-calculated fare quote | Requires customer role, database, routing flag and configured road-routing provider |
| `POST /v1/rides` | Request a ride from a fare quote | Requires customer role, dispatch flag, valid quote, PIN secret and a nearby verified driver with a fresh location; no driver means no booking |
| `GET /v1/rides/:rideId` | Read ride status | Limited to the rider, assigned driver or admin |
| `POST /v1/rides/:rideId/cancel` | Cancel a ride | Enforces ownership and allowed state transitions |
| `POST /v1/rides/:rideId/status` | Driver ride progression | Assigned driver only; trip start requires the customer pickup PIN |
| `POST /v1/support/cases` | Customer/driver support intake | Feature-flagged; optional ride reference must belong to the requester |
| `GET /v1/admin/support/cases` | Support queue | Active Admin/Support role only |
| `PATCH /v1/admin/support/cases/:caseId` | Update/assign support case | Active Admin/Support role, valid assignee and mandatory audit reason |

Unknown endpoints return 404. Protected operations fail closed when authentication, database, routing, dispatch or support configuration is unavailable. These routes do not constitute a complete production ride-hailing service.

## Local development

Requirements: Node.js 22+, Docker Compose, and a local-only environment.

1. From `backend/`, start the local PostGIS database: `docker compose up -d database`.
2. Apply `migrations/001_initial.sql` to that database. The migration enables PostGIS; the database role must have the required permission.
3. Copy `.env.example` to `.env` and use local-only values. Do not commit real credentials.
4. Install dependencies with `npm install`.
5. Run `npm run typecheck` and `npm test`.
6. Start the API with `npm run dev`. For the containerized local stack, use `docker compose up --build`; the API port and database port are bound to localhost by default.

The example Compose stack intentionally leaves payments, routing, dispatch, support and safety flags disabled. It does not create real bookings.

## Configuration and operational prerequisites

- **Identity:** configure `AUTH_JWKS_URL`, `AUTH_ISSUER` and `AUTH_AUDIENCE` for the chosen identity provider. Provision users by matching the verified issuer and subject to `app_users.auth_issuer` and `auth_subject`, with the correct role and active status. Never trust a client-supplied role.
- **Database:** configure `DATABASE_URL`; set `DATABASE_SSL=true` for TLS with certificate verification in deployments that require it.
- **Routing and fare policy:** configure `FEATURE_ROUTING_ENABLED=true`, `ROUTING_BASE_URL` for a trusted OSRM-compatible service, and review all `FARE_*` values before quoting real prices. Quotes expire after five minutes.
- **Ride dispatch and pickup verification:** dispatch remains disabled until the environment is operationally ready. Configure a random secret of at least 32 characters in `RIDE_PIN_SECRET`; never ship it in a mobile app. Dispatch currently requires verified, active drivers with locations recorded within two minutes and within the configured search radius.
- **Support:** enable customer/driver support only after staffing, access controls, privacy handling and escalation procedures are ready.
- **Payments:** keep `FEATURE_PAYMENTS_ENABLED=false` and `FEATURE_PAYMENTS_MODE=disabled`. Provider signature-verification utilities exist, but complete payment-intent, capture/refund, webhook processing and reconciliation workflows are not implemented. Do not set live mode.
- **Secrets:** use a deployment secret manager. Never put identity, database, pickup-PIN or payment secrets in Flutter apps, source control, logs or build artifacts.

## Security and correctness notes

- Fare calculation is server-side and uses integer minor units. A quote must belong to the requesting customer and be unexpired before booking.
- Ride creation uses an idempotency key and a database transaction; driver assignment is locked transactionally to reduce double assignment.
- Pickup PINs are generated with a cryptographically secure random generator and stored as HMAC hashes. A failed PIN must not start a trip.
- Ride and support changes create event/audit records where implemented. Review event payloads and logs before production to prevent unnecessary disclosure of location or personal data.
- CORS is deny-by-default unless explicit origins are configured, Helmet is enabled, and common authorization/cookie/credential fields are redacted from request logs.
- Current CI runs Flutter analyze/tests for all three apps and backend typecheck/tests. It is an engineering gate, not proof of end-to-end or production readiness.

## Release blockers — do not skip

1. Integrate the apps with the real API and identity provider; remove demo-only ride actions without pretending they booked a ride.
2. Implement and test driver onboarding, document verification, secure location updates, availability controls, admin ride/driver operations, and safe dispatch reassignment.
3. Complete and independently test payment intents, verified webhooks, idempotent capture/refund handling, reconciliation and support dispute workflows before enabling any payment method.
4. Add rate limiting/abuse controls, monitoring and alerting, database backup/restore drills, retention/deletion rules, incident response, and a reviewed production deployment configuration.
5. Run integration tests against PostGIS and the selected identity/routing providers, plus end-to-end tests across Customer, Driver Partner and Admin, including concurrency, cancellation, stale driver location, PIN failures and recovery paths.
6. Verify privacy, safety/SOS escalation, legal/compliance requirements, app signing, store release checks and rollback procedures.

Do not merge this engineering branch to `main`, deploy it, enable live payments or publish release APKs until these gates are reviewed and explicitly cleared.
