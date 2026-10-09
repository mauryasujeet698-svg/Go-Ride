import test from "node:test";
import assert from "node:assert/strict";
import { calculateFare, loadFarePolicy } from "./fare-pricing.js";

const policy = { baseFareMinor: 3000, perKilometerMinor: 1200, perMinuteMinor: 200, minimumFareMinor: 5000, version: "test-v1", currency: "INR" };

test("calculates fare in integer minor units using road distance and duration", () => {
 assert.equal(calculateFare({ distanceMeters: 2500, durationSeconds: 600 }, policy), 8000);
});
test("applies minimum fare and rejects absent or invalid routes", () => {
 assert.equal(calculateFare({ distanceMeters: 100, durationSeconds: 30 }, policy), 5000);
 assert.throws(() => calculateFare({ distanceMeters: 0, durationSeconds: 30 }, policy));
 assert.throws(() => calculateFare({ distanceMeters: 100, durationSeconds: -1 }, policy));
});
test("rejects malformed fare policy environment values", () => {
 assert.throws(() => loadFarePolicy({ FARE_BASE_MINOR: "-3" }));
 assert.throws(() => loadFarePolicy({ FARE_CURRENCY: "rupees" }).currency === "rupees" ? new Error("expected INR validation") : undefined);
});
