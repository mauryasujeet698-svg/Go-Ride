import { Buffer } from "node:buffer";
import { z } from "zod";
import { verifyHmacSha256 } from "./webhook-signature.js";
import { assertPaymentAmount, PaymentUnavailableError, type CreatePaymentIntent, type PaymentMode, type PaymentProvider, type PaymentStatus, type ProviderPaymentIntent, type VerifiedPaymentEvent } from "./provider.js";

const orderResponseSchema = z.object({
 id: z.string().min(1),
 amount: z.number().int().nonnegative(),
 currency: z.string().length(3),
 status: z.string()
});
const refundResponseSchema = z.object({ id: z.string().min(1), status: z.string() });
const webhookSchema = z.object({
 event: z.string(),
 created_at: z.number().optional(),
 payload: z.object({
  payment: z.object({ entity: z.object({ id: z.string(), order_id: z.string().optional(), amount: z.number().int(), currency: z.string().length(3), status: z.string() }) }).optional(),
  refund: z.object({ entity: z.object({ id: z.string(), payment_id: z.string().optional(), amount: z.number().int().optional(), currency: z.string().length(3).optional(), status: z.string() }) }).optional()
 })
});

export type RazorpayConfig = {
 keyId: string;
 keySecret: string;
 webhookSecret: string;
 mode: Exclude<PaymentMode, "disabled">;
 fetchImpl?: typeof fetch;
};

function mapPaymentStatus(status: string): PaymentStatus {
 switch (status.toLowerCase()) {
  case "created": return "CREATED";
  case "authorized": return "AUTHORIZED";
  case "captured": return "PAID";
  case "failed": return "FAILED";
  case "refunded": return "REFUNDED";
  case "processed": return "REFUNDED";
  case "pending": return "PENDING";
  default: return "RECONCILIATION_REQUIRED";
 }
}

/**
 * Server-side Razorpay adapter. Never instantiate this in the mobile apps.
 * Use test keys for mode=test and a separately approved secret set for mode=live.
 */
export class RazorpayPaymentProvider implements PaymentProvider {
 readonly name = "razorpay";
 private readonly fetchImpl: typeof fetch;

 constructor(private readonly config: RazorpayConfig) {
  if (!config.keyId.trim() || !config.keySecret.trim() || !config.webhookSecret.trim()) {
   throw new PaymentUnavailableError("Razorpay keys and webhook secret must be configured in the backend secret store.");
  }
  this.fetchImpl = config.fetchImpl ?? fetch;
 }

 async createIntent(input: CreatePaymentIntent): Promise<ProviderPaymentIntent> {
  if (input.mode !== this.config.mode) throw new PaymentUnavailableError("Requested payment mode does not match configured Razorpay credentials.");
  assertPaymentAmount(input.amountMinor, input.currency);
  const response = await this.fetchImpl("https://api.razorpay.com/v1/orders", {
   method: "POST",
   headers: {
    authorization: "Basic " + Buffer.from(this.config.keyId + ":" + this.config.keySecret).toString("base64"),
    "content-type": "application/json"
   },
   body: JSON.stringify({
    amount: input.amountMinor,
    currency: input.currency,
    receipt: input.paymentId.slice(0, 40),
    notes: { ride_id: input.rideId, internal_payment_id: input.paymentId }
   }),
   signal: AbortSignal.timeout(10000)
  });
  if (!response.ok) throw new Error("Razorpay order creation failed with HTTP " + response.status);
  const order = orderResponseSchema.parse(await response.json());
  if (order.amount !== input.amountMinor || order.currency !== input.currency || order.status !== "created") {
   throw new Error("Razorpay order response did not match the requested amount, currency or expected state.");
  }
  return { provider: this.name, providerOrderId: order.id, status: "CREATED" };
 }

 verifyWebhook(rawBody: Buffer, signature: string): VerifiedPaymentEvent {
  if (!verifyHmacSha256(rawBody, signature, this.config.webhookSecret)) {
   throw new Error("Invalid Razorpay webhook signature.");
  }
  const event = webhookSchema.parse(JSON.parse(rawBody.toString("utf8")));
  if (event.payload.payment?.entity) {
   const payment = event.payload.payment.entity;
   const status = event.event === "payment.captured" ? "PAID"
    : event.event === "payment.failed" ? "FAILED"
    : mapPaymentStatus(payment.status);
   return {
    providerEventId: event.event + ":" + payment.id + ":" + String(event.created_at ?? 0),
    providerPaymentId: payment.id,
    status,
    amountMinor: payment.amount,
    currency: payment.currency,
    occurredAt: new Date((event.created_at ?? Math.floor(Date.now() / 1000)) * 1000)
   };
  }
  if (event.payload.refund?.entity) {
   const refund = event.payload.refund.entity;
   return {
    providerEventId: event.event + ":" + refund.id + ":" + String(event.created_at ?? 0),
    providerPaymentId: refund.payment_id ?? refund.id,
    status: event.event === "refund.processed" ? "REFUNDED" : event.event === "refund.created" ? "REFUND_PENDING" : "RECONCILIATION_REQUIRED",
    amountMinor: refund.amount ?? 0,
    currency: refund.currency ?? "INR",
    occurredAt: new Date((event.created_at ?? Math.floor(Date.now() / 1000)) * 1000)
   };
  }
  throw new Error("Unsupported Razorpay webhook payload; reconciliation is required.");
 }

 async refund(input: { providerPaymentId: string; amountMinor?: number; idempotencyKey: string }): Promise<{ providerRefundId: string; status: PaymentStatus }> {
  if (!input.providerPaymentId.trim() || !input.idempotencyKey.trim()) throw new Error("Payment ID and internal idempotency key are required.");
  if (input.amountMinor !== undefined) assertPaymentAmount(input.amountMinor, "INR");
  const response = await this.fetchImpl("https://api.razorpay.com/v1/payments/" + encodeURIComponent(input.providerPaymentId) + "/refund", {
   method: "POST",
   headers: {
    authorization: "Basic " + Buffer.from(this.config.keyId + ":" + this.config.keySecret).toString("base64"),
    "content-type": "application/json"
   },
   body: JSON.stringify(input.amountMinor === undefined ? {} : { amount: input.amountMinor }),
   signal: AbortSignal.timeout(10000)
  });
  if (!response.ok) throw new Error("Razorpay refund request failed with HTTP " + response.status);
  const refund = refundResponseSchema.parse(await response.json());
  return { providerRefundId: refund.id, status: mapPaymentStatus(refund.status) };
 }
}
