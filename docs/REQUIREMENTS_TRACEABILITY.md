# Go-Ride Requirements Traceability and Release Gates

## Scope guard
Only ride-hailing. No delivery, parcel logistics, bus/train/air travel, hotels or general travel services. Customer, driver and admin surfaces remain separate. Delivery-partner app is not present in the audited main tree; verify its source/status before any action.

## Traceability matrix
| Requirement | Main snapshot status | Target area | Required evidence |
|---|---|---|---|
| Ride/driver/fare types | Foundation | domain entities | Domain tests and contract review |
| Ride lifecycle | Foundation | state machine + backend | Transition matrix and server integration tests |
| Realtime reconciliation | Foundation/interfaces | sync + backend events | Out-of-order/gap/reconnect tests |
| Customer home/trips/profile | Prototype | customer feature modules | Widget tests and UX review |
| Real map/current location | Partial only in open PR #8; not main | map/location adapters | Permission, attribution and device tests |
| Place search/reverse geocoding | Missing live implementation | provider adapter/API | Provider contract and launch-zone coverage |
| Road route/polyline/ETA | Missing live implementation | routing provider | Route integration tests; no fabricated fallback |
| Authoritative fare quote | Missing backend | fare module + customer UI | Expiry/tampering/currency tests |
| Durable booking API | Missing backend | ride module | Database and duplicate-request tests |
| Driver auth/onboarding | Missing in this repo | driver app/backend | Auth and verification tests |
| Driver availability/location | Missing live implementation | driver app + dispatch | Freshness, consent and spoof/stale tests |
| Atomic dispatch | Missing backend | dispatch module | Concurrency/no-double-assignment tests |
| Pickup PIN | Field exists; live verification missing | backend lifecycle + clients | Incorrect/expired/replay/guessing tests |
| Cancellation/completion | UI prototype/foundation only | backend + clients | Race, reason, retry and snapshot tests |
| Active ride recovery | Sync foundation only | API repository/realtime | Process-death/reconnect integration tests |
| Trip history/receipt/rating | Missing persistence | history module + customer app | End-to-end persistence tests |
| Customer/driver support | Missing operational lifecycle | support module + clients/admin | Case lifecycle/access tests |
| Safety/SOS/trip share | No verified operations found | safety module | Runbook ownership and escalation tests |
| Admin roles/audit | Admin app/backend missing | admin console + API | RBAC matrix and audit tests |
| Payment/UPI reconciliation | Missing | payment adapter/backend ledger | Signature/replay/refund/reconciliation tests |
| Privacy/deletion | Not evidenced | API/data lifecycle | Retention matrix, deletion test and review |
| Branch protection/scanning | Not configured in observed settings | GitHub settings/workflows | Owner verifies settings |
| Release build | Workflow exists; auto-triggers on PR to main | build workflow | Explicit authorization, artifact, source SHA/checksum |
| Delivery-partner app | Not in audited main tree | source to be identified | Owner confirms intended repo/status |

## Implementation-ready definition
- No unresolved design decision that changes data model, vendor integration or safety operation.
- API contract/schema is versioned.
- Customer and driver journeys use real backend repositories, not local demo success.
- Admin controls are server-authorized and audited.
- Unit/widget/API/integration tests cover failure and concurrency.
- Secrets, permissions, privacy and retention have been reviewed.
- Every visible action is functional or intentionally disabled with an explanation.
- No fake route, fare, assignment, safety response or payment result.
- Environment configuration and remaining limitations are documented.

## Build-ready definition
- Implementation-ready criteria have evidence.
- Dependency/code generation/static analysis/unit/widget/integration checks not producing the release APK pass where supported.
- Android permissions, package identity, versioning, signing approach and environment config are reviewed.
- Workflow trigger is understood and explicitly authorized.
- APK is tied to an exact commit and has checksum/provenance metadata.

A build-ready status cannot honestly be assigned from source-only review without required checks and integration tests. The Android build remains blocked until explicit authorization.