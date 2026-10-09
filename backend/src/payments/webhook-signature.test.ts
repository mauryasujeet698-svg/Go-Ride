import test from "node:test";
import assert from "node:assert/strict";
import { createHmacSha256ForTest, verifyHmacSha256 } from "./webhook-signature.js";

test("accepts a valid HMAC signature over the raw body", () => {
 const body = Buffer.from('{"event":"payment.paid","amount":1200}');
 const signature = createHmacSha256ForTest(body, "test-secret");
 assert.equal(verifyHmacSha256(body, signature, "test-secret"), true);
 assert.equal(verifyHmacSha256(body, "sha256=" + signature, "test-secret"), true);
});
test("rejects altered bodies, malformed signatures and missing secrets", () => {
 const body = Buffer.from('{"event":"payment.paid"}');
 const signature = createHmacSha256ForTest(body, "test-secret");
 assert.equal(verifyHmacSha256(Buffer.from('{"event":"payment.failed"}'), signature, "test-secret"), false);
 assert.equal(verifyHmacSha256(body, "nope", "test-secret"), false);
 assert.equal(verifyHmacSha256(body, signature, ""), false);
});
