import test from "node:test";
import assert from "node:assert/strict";
import { buildServer } from "./server.js";

test("liveness and capability endpoints work without claiming database readiness", async () => {
 const previousUrl = process.env.DATABASE_URL;
 const previousMode = process.env.FEATURE_PAYMENTS_MODE;
 const previousEnabled = process.env.FEATURE_PAYMENTS_ENABLED;
 delete process.env.DATABASE_URL;
 process.env.FEATURE_PAYMENTS_MODE = "disabled";
 process.env.FEATURE_PAYMENTS_ENABLED = "false";
 const { app } = await buildServer();
 try {
  const live = await app.inject({ method: "GET", url: "/health/live" });
  assert.equal(live.statusCode, 200);
  assert.deepEqual(live.json(), { status: "ok" });
  const ready = await app.inject({ method: "GET", url: "/health/ready" });
  assert.equal(ready.statusCode, 503);
  const capabilities = await app.inject({ method: "GET", url: "/v1/capabilities" });
  assert.equal(capabilities.statusCode, 200);
  assert.equal(capabilities.json().payments.enabled, false);
  assert.equal(capabilities.json().payments.mode, "disabled");
  const missing = await app.inject({ method: "GET", url: "/v1/rides" });
  assert.equal(missing.statusCode, 404);
 } finally {
  await app.close();
  if (previousUrl === undefined) delete process.env.DATABASE_URL; else process.env.DATABASE_URL = previousUrl;
  if (previousMode === undefined) delete process.env.FEATURE_PAYMENTS_MODE; else process.env.FEATURE_PAYMENTS_MODE = previousMode;
  if (previousEnabled === undefined) delete process.env.FEATURE_PAYMENTS_ENABLED; else process.env.FEATURE_PAYMENTS_ENABLED = previousEnabled;
 }
});
