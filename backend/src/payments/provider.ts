export type PaymentMode = "disabled" | "test" | "live";
export type PaymentStatus =
  | "CREATED"
  | "PENDING"
  | "AUTHORIZED"
  | "PAID"
  | "FAILED"
  | "CANCELLED"
  | "REFUND_PENDING"
  | "REFUNDED"
  | "RECONCILIATION_REQUIRED";

export interface CreatePaymentIntent {
  rideId: string;
  paymentId: string;
  amountMinor: number;
  currency: string;
  idempotencyKey: string;
  mode: Exclude<PaymentMode, "disabled">;
}

export interface ProviderPaymentIntent {
  provider: string;
  providerPaymentId: string;
  status: PaymentStatus;
  checkoutUrl?: string;
}

export interface VerifiedPaymentEvent {
  providerEventId: string;
  providerPaymentId: string;
  status: PaymentStatus;
  amountMinor: number;
  currency: string;
  occurredAt: Date;
}

/**
 * Adapter contract only. A real provider adapter must be implemented and tested
 * against provider sandbox docs before payments can be enabled.
 */
export interface PaymentProvider {
  readonly name: string;
  createIntent(input: CreatePaymentIntent): Promise<ProviderPaymentIntent>;
  verifyWebhook(rawBody: Buffer, signature: string): VerifiedPaymentEvent;
  refund(input: { providerPaymentId: string; amountMinor?: number; idempotencyKey: string }): Promise<{ providerRefundId: string; status: PaymentStatus }>;
}

export class PaymentUnavailableError extends Error {
  constructor(message = "Payments are not configured for this environment.") {
    super(message);
    this.name = "PaymentUnavailableError";
  }
}

export function assertPaymentAmount(amountMinor: number, currency: string): void {
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) {
    throw new Error("Payment amount must be a positive integer in minor currency units.");
  }
  if (!/^[A-Z]{3}$/.test(currency)) {
    throw new Error("Currency must be an ISO 4217 uppercase code.");
  }
}
