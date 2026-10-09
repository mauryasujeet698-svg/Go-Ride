# Three-App Scope, Payment Gateway and Feature Availability Plan

## Binding product decision
Go-Ride consists of exactly three product apps/surfaces:
1. Customer app (Flutter/Android first).
2. Driver Partner app (separate Flutter app).
3. Admin app/console (recommended responsive web console unless existing source proves a different committed decision).

Ride-hailing only. The delivery-partner app is not one of these three Go-Ride ride-hailing apps and is not present in the audited main tree. Do not merge delivery workflows into Go-Ride.

## Build all planned features, enable only what is operationally available
Use server-controlled, environment-specific feature configuration. A feature can be implemented and tested while disabled for customers. Do not show options that cannot actually be fulfilled in the selected launch zone or environment.

Every feature should have:
- A code-level capability and explicit configuration key.
- Backend enforcement; hiding a button is not access control.
- An Admin-visible status: unavailable, disabled, test-only, enabled, degraded or retired.
- A reason/status message and effective time where useful.
- Automated tests for enabled and disabled behavior.
- An audit event for privileged changes.
- Dependencies and prerequisites, so a feature cannot be enabled until required providers and operational processes are ready.

Suggested configuration examples (not hard-coded constants):
- `payments.enabled`
- `payments.mode` (`disabled`, `test`, `live`)
- `payments.methods.upi.enabled`
- `payments.methods.cards.enabled`
- `payments.methods.netbanking.enabled`
- `payments.cash.enabled`
- `ride_categories.bike.enabled`, `ride_categories.auto.enabled`, `ride_categories.cab.enabled`
- `maps.search.enabled`, `maps.routing.enabled`, `driver_dispatch.enabled`
- `safety.trip_sharing.enabled`, `safety.sos.enabled`
- `support.customer.enabled`, `support.driver.enabled`
- `driver_onboarding.enabled`, `driver_payouts.enabled`

Use a typed, versioned server configuration with environment/zone scope and audit history. Never expose secrets in config sent to apps. Client flags control presentation only; server-side policy controls actual actions. A cached config must have a safe expiry and fail closed for money movement and safety operations.

## Payment gateway: build integration now, keep real payments off
Payment support is a required planned capability, but real payment collection remains unavailable until the owner completes provider onboarding, configures credentials securely, passes end-to-end sandbox checks and explicitly enables live mode.

Recommended implementation approach:
1. Create a provider-neutral payment interface and a single server-side payment module.
2. Pick one gateway for the first launch after checking fees, settlement, UPI/cards/netbanking support, refunds, support, business KYC and India-specific terms. Razorpay is one candidate, not a final selection.
3. Implement sandbox/test integration first. Keep live credentials out of source control and out of mobile apps; use a server-side secret store.
4. Server creates an order/payment intent for the authoritative ride fare. Never trust the client-submitted amount.
5. Verify gateway signatures server-side and reconcile using signed webhooks plus provider API status. A client success callback alone never marks a payment paid.
6. Store an internal payment record and append-only financial events. Handle pending, authorized, captured/paid, failed, cancelled, refund-pending, refunded and reconciliation-required states separately from ride status.
7. Make order creation, webhook processing, capture and refund idempotent. Verify amount, currency, ride/order linkage and event freshness; safely handle duplicate and out-of-order webhooks.
8. Test success, failure, abandonment, timeout, app kill, network loss, duplicate callback/webhook, late success, refund and mismatch cases.
9. Default `payments.mode=disabled` until test mode passes. Test mode may be used only when sandbox credentials are supplied; it must never accept real money.
10. Keep `payments.mode=live` impossible to enable unless live account activation/KYC, live keys, required payment methods, webhook verification, refund/reconciliation runbook and owner approval are confirmed.

Cash can be represented as a separate payment method, but it too must be configured per launch zone and reconciled in trip completion/driver settlement. Do not imply UPI, cash or cards are available until their exact operational paths are configured.

Official reference: Razorpay documents separate Test and Live modes and separate API keys; Test mode simulates transactions and does not accept real money. Live mode requires account activation. Some payment methods require provider approval. See https://github.com/razorpay/markdown-docs/blob/master/payments/dashboard/test-live-modes.md and https://github.com/razorpay/markdown-docs/blob/master/payments/payment-gateway/flutter-integration/standard/integration-steps.md . This is a reference for implementation mechanics, not a final gateway decision.

## Admin responsibilities
Admin should be the operational control plane, not a way to bypass server safety:
- Configure launch zones, ride categories, fares and feature availability.
- Enable/disable payment methods per environment/zone, view provider health and reconciliation status.
- Manage customer/driver support cases, safety escalation and incident ownership.
- Review driver documents and manage eligibility.
- Inspect ride timelines, cancellations, dispatch failures and audit events.
- Apply role-based access and record who changed what, when, and why.
- Prevent enabling a feature with missing prerequisites; show actionable blocker messages.
- Never display secret keys. Credential rotation is done through a secure secret-management workflow, not a text field in a general admin screen.

## Remaining delivery steps
1. Complete repository/branch/PR/issue audit and confirm whether any separate driver/admin/delivery repositories exist.
2. Finalize product decisions: launch city/zone, vehicle categories, map/routing provider, OTP provider, hosting region, payment gateway, initial cash/UPI/card availability, support hours and safety escalation ownership.
3. Finalize data model and API/OpenAPI contract for auth, quote, rides, dispatch, driver profile, payment ledger, support, feature config and admin audit.
4. Implement backend and database migrations first for authoritative ride state, idempotency, fare quotes, role access, feature config and payment ledger.
5. Refactor customer Flutter UI into feature modules and wire real API repositories.
6. Build the separate driver-partner Flutter app against the same server contract.
7. Build the admin console with RBAC, feature flags, support/safety, driver verification, ride monitoring and payment reconciliation.
8. Integrate map search/routing, OTP, notifications and payment gateway sandbox. Use provider abstractions where substitution is realistic.
9. Add automated unit, widget, API, integration, concurrency, security, offline/reconnect, accessibility and device tests.
10. Conduct independent source/security/UX review; resolve all high-risk blockers and document known limitations.
11. Run non-release verification checks where possible without triggering the Android release workflow.
12. Only after explicit user approval, trigger the release build, inspect the artifact and logs, and report exact commit SHA, workflow status, APK and checksum.

## Release gates
- Gate A — design-ready: scope, provider choices, API contract and operational ownership are documented.
- Gate B — implementation-complete: all required paths exist in all three apps and backend; feature flags work; no dead buttons or fake success.
- Gate C — verification-complete: required tests pass; security/privacy review and end-to-end pilot flows pass.
- Gate D — pilot-ready: launch zone, driver supply, support staffing, incident escalation, legal/provider approvals and monitoring are in place.
- Gate E — build authorization: owner explicitly approves release workflow. No build before this gate.
- Gate F — live payments: separate approval after provider account activation, live keys, webhook validation, reconciliation/refund runbook and a successful controlled go-live check.

Passing Gate E does not automatically pass Gate F. The APK may be built while real payments and other unavailable capabilities remain disabled.