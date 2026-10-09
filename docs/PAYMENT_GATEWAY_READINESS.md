# Payment gateway decision and readiness

## Initial gateway choice: Razorpay (India-first)

Razorpay is selected as the initial adapter target for Go-Ride's India-first ride-hailing pilot because its official docs expose a server-side Orders API, payment verification guidance, refunds and webhook signature validation. This is an engineering choice, not proof that a merchant account has been approved or that every payment method is available.

Official references:
- Orders API: https://razorpay.com/docs/api/orders/
- Server integration and signature verification: https://razorpay.com/docs/server-integration/python/test-app/
- Webhook signature validation and event-ordering guidance: https://github.com/razorpay/markdown-docs/blob/master/webhooks/validate-test.md
- Test and Live modes use different API keys: https://github.com/razorpay/markdown-docs/blob/master/payments/dashboard/test-live-modes.md

## Implemented in this branch

- Provider-neutral payment contract.
- Initial server-side Razorpay order/refund adapter.
- HMAC-SHA256 verification over the exact raw webhook body.
- Sandbox-focused adapter tests using a mocked HTTP response.
- Payment status model separate from ride status.
- Environment placeholders; no real credentials committed.

## Still required before a real sandbox end-to-end flow

- Persist an internal payment attempt before calling the provider and reconcile ambiguous timeouts without creating duplicate customer charges/orders.
- Add authenticated API endpoints for creating payment orders, verifying checkout callback signatures against the order ID stored on the server, querying payment status, processing webhooks idempotently and requesting refunds.
- Verify every webhook's order/payment/ride association, amount, currency and valid state transition in a database transaction.
- Add rate limiting, request-size limits, replay/duplicate-event handling and monitoring.
- Add a provider-enabled integration test against a merchant's Test Mode credentials and a publicly reachable staging webhook endpoint.
- Complete gateway business onboarding, payment-method approvals and support/refund/reconciliation procedures.

## Live mode gate

Live payment mode remains disabled by default. Do not enable it until merchant account activation/KYC, live keys in a secret manager, live webhook configuration, test evidence, refund/reconciliation runbook, monitoring and explicit owner approval are complete. The adapter alone is not a production payment system.
