import test from "node:test";
import assert from "node:assert/strict";
import { loadFeatureConfig } from "./features.js";

test("all externally dependent features default to disabled", () => {
 const config = loadFeatureConfig({});
 assert.equal(config.payments.enabled, false);
 assert.equal(config.payments.mode, "disabled");
 assert.equal(config.payments.methods.upi, false);
 assert.equal(config.maps.search, false);
 assert.equal(config.maps.routing, false);
 assert.equal(config.dispatch.enabled, false);
 assert.equal(config.safety.sos, false);
});

test("rejects payment methods when payment mode is disabled", () => {
 assert.throws(() => loadFeatureConfig({ FEATURE_PAYMENT_UPI_ENABLED: "true" }), /cannot be enabled/);
});

test("rejects live mode unless payment feature is explicitly enabled", () => {
 assert.throws(() => loadFeatureConfig({ FEATURE_PAYMENTS_MODE: "live" }), /requires FEATURE_PAYMENTS_ENABLED/);
});
