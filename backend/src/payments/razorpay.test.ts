import test from "node:test";
import assert from "node:assert/strict";
import { RazorpayPaymentProvider } from "./razorpay.js";
import { createHmacSha256ForTest } from "./webhook-signature.js";

function provider(fetchImpl: typeof fetch = fetch) {
 return new RazorpayPaymentProvider({ keyId: "rzp_test_key", keySecret: "test-secret", webhookSecret: "webhook-secret", mode: "test", fetchImpl });
}

test("creates server-side order and checks amount and currency", async () => {
 let requestBody = "";
 const fakeFetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
  requestBody = String(init?.body ?? "");
  return new Response(JSON.stringify({ id: "order_test_123", amount: 12500, currency: "INR", status: "created" }), { status: 200 });
 }) as typeof fetch;
 const result = await provider(fakeFetch).createIntent({ rideId: "ride-1", paymentId: "payment-1", amountMinor: 12500, currency: "INR", idempotencyKey: "internal-key-123456", mode: "test" });
 assert.equal(result.providerOrderId, "order_test_123");
 assert.equal(result.status, "CREATED");
 assert.equal(JSON.parse(requestBody).amount, 12500);
});

test("rejects mismatched amount and provider mode", async () => {
 const wrongAmount = (async () => new Response(JSON.stringify({ id: "order_bad", amount: 100, currency: "INR", status: "created" }), { status: 200 })) as typeof fetch;
 await assert.rejects(() => provider(wrongAmount).createIntent({ rideId: "r", paymentId: "p", amountMinor: 12500, currency: "INR", idempotencyKey: "internal-key-123456", mode: "test" }));
 await assert.rejects(() => provider().createIntent({ rideId: "r", paymentId: "p", amountMinor: 12500, currency: "INR", idempotencyKey: "internal-key-123456", mode: "live" }));
});

test("verifies webhook signature before interpreting captured payment", () => {
 const raw = Buffer.from(JSON.stringify({ event: "payment.captured", created_at: 1770000000, payload: { payment: { entity: { id: "pay_123", order_id: "order_123", amount: 12500, currency: "INR", status: "captured" } } } }));
 const signature = createHmacSha256ForTest(raw, "webhook-secret");
 const result = provider().verifyWebhook(raw, signature);
 assert.equal(result.status, "PAID");
 assert.equal(result.providerPaymentId, "pay_123");
 assert.equal(result.amountMinor, 12500);
 assert.throws(() => provider().verifyWebhook(raw, "invalid"));
});
