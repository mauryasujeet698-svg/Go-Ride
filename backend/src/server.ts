import "dotenv/config";
import Fastify from "fastify";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import pg from "pg";
import { randomUUID } from "node:crypto";
import { loadFeatureConfig } from "./config/features.js";

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
 let pool: pg.Pool | undefined;
 if (process.env.DATABASE_URL?.trim()) {
  const options: pg.PoolConfig = { connectionString: requiredEnv("DATABASE_URL"), max: 10, connectionTimeoutMillis: 3000, idleTimeoutMillis: 30000 };
  if (process.env.DATABASE_SSL === "true") options.ssl = { rejectUnauthorized: true };
  pool = new Pool(options);
  pool.on("error", (error: Error) => app.log.error({ err: error }, "Unexpected database pool error"));
 }
 app.get("/health/live", async () => ({ status: "ok" }));
 app.get("/health/ready", async (_request, reply) => {
  if (!pool) return reply.code(503).send({ status: "not_ready", reason: "database_not_configured" });
  try { await pool.query("SELECT 1"); return { status: "ready" }; }
  catch { return reply.code(503).send({ status: "not_ready", reason: "database_unavailable" }); }
 });
 // Presentation hints only; secrets are never returned and these flags are not authorization.
 app.get("/v1/capabilities", async () => ({
  payments: { enabled: features.payments.enabled, mode: features.payments.mode, methods: features.payments.methods },
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
async function main() {
 const { app, host, port } = await buildServer();
 await app.listen({ host, port });
}
if (process.env.NODE_ENV !== "test") {
 main().catch((error: unknown) => {
  process.stderr.write("Go-Ride API failed to start: " + (error instanceof Error ? error.message : "unknown error") + "\n");
  process.exitCode = 1;
 });
}
