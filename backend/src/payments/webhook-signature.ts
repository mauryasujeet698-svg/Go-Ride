import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Verifies an HMAC-SHA256 signature over the exact raw request body.
 * The provider adapter must normalize its documented signature encoding before calling this.
 * Never parse and re-serialize JSON before verification.
 */
export function verifyHmacSha256(rawBody: Buffer, providedSignature: string, secret: string): boolean {
 if (!secret || !providedSignature) return false;
 const supplied = providedSignature.trim().replace(/^sha256=/i, "");
 if (!/^[a-f0-9]{64}$/i.test(supplied)) return false;
 const expected = createHmac("sha256", secret).update(rawBody).digest();
 const actual = Buffer.from(supplied, "hex");
 return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function createHmacSha256ForTest(rawBody: Buffer, secret: string): string {
 return createHmac("sha256", secret).update(rawBody).digest("hex");
}
