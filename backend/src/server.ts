import "dotenv/config";
import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import pg from "pg";
import { randomUUID } from "node:crypto";
import { loadFeatureConfig } from "./config/features.js";
import { createAccessTokenVerifier, AuthenticationConfigurationError } from "./auth/jwt.js";
import { verifyRequestPrincipal } from "./auth/fastify-auth.js";
import { z } from "zod";
import { OsrmCompatibleRoutingProvider } from "./routing/osrm-provider.js";
import { calculateFare, loadFarePolicy } from "./routing/fare-pricing.js";
import { registerRideRoutes } from "./routes/ride-routes.js";
import { registerSupportRoutes } from "./routes/support-routes.js";

const { Pool } = pg;
function requiredEnv(name: string): string {
 const value = process.env[name]?.trim();
 if (!value) throw new Error("Missing required environment variable: " + name);
 return value;
}
export async function buildServer() {
 const host = process.env.HOST ?? "127.0.0.1";
 const port = Number(process.env.PORT ?? "8080");
 if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error("PORT must be a valid TCP port.");
 const app = Fastify({
  logger: { level: process.env.LOG_LEVEL ?? "info", redact: { paths: ["req.headers.authorization", "req.headers.cookie", "req.body.phone", "req.body.otp", "req.body.token", "req.body.password"], censor: "[REDACTED]" } },
  requestIdHeader: "x-request-id", genReqId: () => randomUUID()
 });
 await app.register(helmet);
 const origins = (process.env.CORS_ORIGINS ?? "").split(",").map((origin) => origin.trim()).filter(Boolean);
 await app.register(cors, { origin: origins.length ? origins : false, credentials: false });
 const features = loadFeatureConfig();
 const routingBaseUrl = process.env.ROUTING_BASE_URL?.trim();
 const routingProvider = features.maps.routing && routingBaseUrl
  ? new OsrmCompatibleRoutingProvider(routingBaseUrl, { production: process.env.NODE_ENV === "production" })
  : null;
 let accessTokenVerifier: ReturnType<typeof createAccessTokenVerifier> | null = null;
 try { accessTokenVerifier = createAccessTokenVerifier(); }
 catch (error) {
  if (!(error instanceof AuthenticationConfigurationError)) throw error;
 }
 let pool: pg.Pool | undefined;
 if (process.env.DATABASE_URL?.trim()) {
  const options: pg.PoolConfig = { connectionString: requiredEnv("DATABASE_URL"), max: 10, connectionTimeoutMillis: 3000, idleTimeoutMillis: 30000 };
  if (process.env.DATABASE_SSL === "true") options.ssl = { rejectUnauthorized: true };
  pool = new Pool(options);
  pool.on("error", (error: Error) => app.log.error({ err: error }, "Unexpected database pool error"));
 }
 await registerRideRoutes(app, { pool, verifier: accessTokenVerifier, features });
 await registerSupportRoutes(app, { pool, verifier: accessTokenVerifier, features });
 app.get("/health/live", async () => ({ status: "ok" }));
 app.get("/health/ready", async (_request, reply) => {
  if (!pool) return reply.code(503).send({ status: "not_ready", reason: "database_not_configured" });
  if (!accessTokenVerifier) return reply.code(503).send({ status: "not_ready", reason: "authentication_not_configured" });
  if (features.maps.routing && !routingProvider) return reply.code(503).send({ status: "not_ready", reason: "routing_not_configured" });
  if (features.dispatch.enabled && (!features.maps.routing || !routingProvider)) {
   return reply.code(503).send({ status: "not_ready", reason: "dispatch_routing_not_configured" });
  }
  if (features.dispatch.enabled && (!process.env.RIDE_PIN_SECRET || process.env.RIDE_PIN_SECRET.trim().length < 32)) {
   return reply.code(503).send({ status: "not_ready", reason: "pickup_verification_not_configured" });
  }
  try { await pool.query("SELECT 1"); return { status: "ready" }; }
  catch { return reply.code(503).send({ status: "not_ready", reason: "database_unavailable" }); }
 });
 app.get("/v1/me", async (request, reply) => {
  const principal = await verifyRequestPrincipal(request, reply, accessTokenVerifier);
  if (!principal) return;
  if (!pool) return reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Account service is unavailable." } });
  const issuer = principal.claims.iss;
  if (typeof issuer !== "string") return reply.code(401).send({ error: { code: "INVALID_TOKEN", message: "The access token has no issuer." } });
  const result = await pool.query("SELECT id, display_name, role, status FROM app_users WHERE auth_issuer = $1 AND auth_subject = $2 LIMIT 1", [issuer, principal.subject]);
  const user = result.rows[0] as { id: string; display_name: string; role: string; status: string } | undefined;
  if (!user || user.status !== "ACTIVE") return reply.code(403).send({ error: { code: "ACCOUNT_UNAVAILABLE", message: "The account is not provisioned or is not active." } });
  return { id: user.id, displayName: user.display_name, role: user.role, status: user.status };
 });
 app.post("/v1/fare-quotes", async (request, reply) => {
  const principal = await verifyRequestPrincipal(request, reply, accessTokenVerifier);
  if (!principal) return;
  if (!pool) return reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Fare quotes are unavailable." } });
  if (!features.maps.routing || !routingProvider) {
   return reply.code(503).send({ error: { code: "ROUTING_UNAVAILABLE", message: "Road routing is not configured; no estimated fare can be provided." } });
  }
  const issuer = principal.claims.iss;
  if (typeof issuer !== "string") return reply.code(401).send({ error: { code: "INVALID_TOKEN", message: "The access token has no issuer." } });
  const accountResult = await pool.query("SELECT id, role, status FROM app_users WHERE auth_issuer = $1 AND auth_subject = $2 LIMIT 1", [issuer, principal.subject]);
  const account = accountResult.rows[0] as { id: string; role: string; status: string } | undefined;
  if (!account || account.status !== "ACTIVE") return reply.code(403).send({ error: { code: "ACCOUNT_UNAVAILABLE", message: "The account is not active." } });
  if (account.role !== "CUSTOMER") return reply.code(403).send({ error: { code: "ROLE_FORBIDDEN", message: "Only customer accounts can request fare quotes." } });
  const bodySchema = z.object({
   pickup: z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) }),
   dropoff: z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) }),
   vehicleCategory: z.string().trim().min(1).max(40)
  }).strict();
  const parsed = bodySchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: { code: "INVALID_REQUEST", message: "Pickup, destination and vehicle category are required." } });
  try {
   const route = await routingProvider.getRoute(parsed.data.pickup, parsed.data.dropoff);
   const policy = loadFarePolicy();
   const amountMinor = calculateFare(route, policy);
   const expiresAt = new Date(Date.now() + 5 * 60 * 1000);
   const saved = await pool.query(
    "INSERT INTO fare_quotes (rider_id, pickup, dropoff, vehicle_category, distance_m, duration_s, amount_minor, currency, pricing_policy_version, route_provider, expires_at) VALUES ($1, ST_SetSRID(ST_MakePoint($2,$3),4326)::geography, ST_SetSRID(ST_MakePoint($4,$5),4326)::geography, $6, $7, $8, $9, $10, $11, $12, $13) RETURNING id, expires_at",
    [account.id, parsed.data.pickup.longitude, parsed.data.pickup.latitude, parsed.data.dropoff.longitude, parsed.data.dropoff.latitude, parsed.data.vehicleCategory, route.distanceMeters, route.durationSeconds, amountMinor, policy.currency, policy.version, route.provider, expiresAt]
   );
   const quote = saved.rows[0] as { id: string; expires_at: Date };
   return reply.code(201).send({
    id: quote.id, vehicleCategory: parsed.data.vehicleCategory,
    fare: { amountMinor, currency: policy.currency, policyVersion: policy.version },
    route: { distanceMeters: route.distanceMeters, durationSeconds: route.durationSeconds, provider: route.provider, geometry: route.geometry },
    expiresAt: quote.expires_at
   });
  } catch (error) {
   request.log.warn({ requestId: request.id, err: error }, "Fare quote could not be calculated");
   return reply.code(503).send({ error: { code: "FARE_QUOTE_UNAVAILABLE", message: "A verified road route and fare could not be calculated. Please try again." } });
  }
 });
 // Presentation hints only; secrets are never returned and these flags are not authorization.
 app.get("/v1/capabilities", async () => ({
  // Fail closed until intent/capture/refund, verified webhook and reconciliation routes exist.
  payments: { enabled: false, mode: "disabled", methods: [] },
  maps: features.maps, dispatch: features.dispatch, support: features.support, safety: features.safety
 }));
 app.setNotFoundHandler(async (_request, reply) => reply.code(404).send({ error: { code: "NOT_FOUND", message: "Endpoint not implemented." } }));
 app.setErrorHandler((error, request, reply) => {
  request.log.error({ err: error, requestId: request.id }, "Request failed");
  return reply.code(500).send({ error: { code: "INTERNAL_ERROR", message: "An unexpected error occurred.", requestId: request.id } });
 });
 app.addHook("onClose", async () => { if (pool) await pool.end(); });
 return { app, host, port };
}
