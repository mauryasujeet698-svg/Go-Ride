import { createHash, createHmac, randomInt, timingSafeEqual } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type pg from "pg";
import { z } from "zod";
import { verifyRequestPrincipal, type AccessTokenVerifier } from "../auth/fastify-auth.js";
import type { FeatureConfig } from "../config/features.js";
import { assertTransition, type RideStatus } from "../domain/ride-state.js";

type Dependencies = {
 pool: pg.Pool | undefined;
 verifier: AccessTokenVerifier | null;
 features: FeatureConfig;
};

type Account = { id: string; role: string; status: string };
type QuoteRow = {
 id: string; rider_id: string; pickup_lat: number; pickup_lon: number;
 dropoff_lat: number; dropoff_lon: number; vehicle_category: string;
 amount_minor: string | number; currency: string; expires_at: Date;
};

async function currentAccount(
 request: FastifyRequest, reply: FastifyReply, pool: pg.Pool | undefined, verifier: AccessTokenVerifier | null
): Promise<Account | null> {
 const principal = await verifyRequestPrincipal(request, reply, verifier);
 if (!principal) return null;
 if (!pool) {
  await reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Ride service is unavailable." } });
  return null;
 }
 const issuer = principal.claims.iss;
 if (typeof issuer !== "string") {
  await reply.code(401).send({ error: { code: "INVALID_TOKEN", message: "The access token has no issuer." } });
  return null;
 }
 const result = await pool.query("SELECT id, role, status FROM app_users WHERE auth_issuer = $1 AND auth_subject = $2 LIMIT 1", [issuer, principal.subject]);
 const account = result.rows[0] as Account | undefined;
 if (!account || account.status !== "ACTIVE") {
  await reply.code(403).send({ error: { code: "ACCOUNT_UNAVAILABLE", message: "The account is not active." } });
  return null;
 }
 return account;
}

const createRideSchema = z.object({
 fareQuoteId: z.string().uuid(),
 idempotencyKey: z.string().trim().min(16).max(128)
}).strict();

export async function registerRideRoutes(app: FastifyInstance, deps: Dependencies): Promise<void> {
 app.post("/v1/rides", async (request, reply) => {
  const account = await currentAccount(request, reply, deps.pool, deps.verifier);
  if (!account) return;
  if (account.role !== "CUSTOMER") return reply.code(403).send({ error: { code: "ROLE_FORBIDDEN", message: "Only customers can request rides." } });
  if (!deps.features.dispatch.enabled) return reply.code(503).send({ error: { code: "DISPATCH_UNAVAILABLE", message: "Driver matching is not enabled for this environment." } });
  const parsed = createRideSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: { code: "INVALID_REQUEST", message: "A valid fare quote and idempotency key are required." } });
  const pinSecret = process.env.RIDE_PIN_SECRET?.trim();
  if (!pinSecret || pinSecret.length < 32) return reply.code(503).send({ error: { code: "RIDE_PIN_NOT_CONFIGURED", message: "Pickup verification is not configured; no ride was booked." } });
  const pool = deps.pool!;
  const requestHash = createHash("sha256").update(JSON.stringify({ fareQuoteId: parsed.data.fareQuoteId })).digest("hex");
  const client = await pool.connect();
  try {
   await client.query("BEGIN");
   const idempotencyInsert = await client.query(
    "INSERT INTO idempotency_records (principal_id, idempotency_key, request_hash, expires_at) VALUES ($1,$2,$3,now() + interval '24 hours') ON CONFLICT DO NOTHING RETURNING idempotency_key",
    [account.id, parsed.data.idempotencyKey, requestHash]
   );
   if (idempotencyInsert.rowCount === 0) {
    const existing = await client.query(
     "SELECT request_hash, response_status, response_body FROM idempotency_records WHERE principal_id = $1 AND idempotency_key = $2 FOR UPDATE",
     [account.id, parsed.data.idempotencyKey]
    );
    const record = existing.rows[0] as { request_hash: string; response_status: number | null; response_body: unknown } | undefined;
    if (!record || record.request_hash !== requestHash) {
     await client.query("ROLLBACK");
     return reply.code(409).send({ error: { code: "IDEMPOTENCY_CONFLICT", message: "This idempotency key was already used for a different request." } });
    }
    if (record.response_status !== null && record.response_body !== null) {
     await client.query("COMMIT");
     return reply.code(record.response_status).send(record.response_body);
    }
    await client.query("ROLLBACK");
    return reply.code(409).send({ error: { code: "REQUEST_IN_PROGRESS", message: "An identical ride request is still being processed." } });
   }

   const quoteResult = await client.query(
    "SELECT id, rider_id, ST_Y(pickup::geometry) AS pickup_lat, ST_X(pickup::geometry) AS pickup_lon, ST_Y(dropoff::geometry) AS dropoff_lat, ST_X(dropoff::geometry) AS dropoff_lon, vehicle_category, amount_minor, currency, expires_at FROM fare_quotes WHERE id = $1 FOR UPDATE",
    [parsed.data.fareQuoteId]
   );
   const quote = quoteResult.rows[0] as QuoteRow | undefined;
   if (!quote || quote.rider_id !== account.id || new Date(quote.expires_at).getTime() <= Date.now()) {
    await client.query("ROLLBACK");
    return reply.code(409).send({ error: { code: "QUOTE_INVALID", message: "The fare quote is missing, expired or does not belong to this customer. Request a new quote." } });
   }

   const driverResult = await client.query(
    "SELECT dp.user_id FROM driver_profiles dp JOIN app_users u ON u.id = dp.user_id WHERE dp.verification_status = 'VERIFIED' AND dp.is_available = true AND u.status = 'ACTIVE' AND dp.last_location IS NOT NULL AND dp.location_recorded_at > now() - interval '2 minutes' AND ST_DWithin(dp.last_location, ST_SetSRID(ST_MakePoint($1,$2),4326)::geography, 10000) AND NOT EXISTS (SELECT 1 FROM rides r WHERE r.driver_id = dp.user_id AND r.status IN ('DRIVER_ASSIGNED','DRIVER_ARRIVING','DRIVER_ARRIVED','IN_PROGRESS')) ORDER BY ST_Distance(dp.last_location, ST_SetSRID(ST_MakePoint($1,$2),4326)::geography) ASC LIMIT 1 FOR UPDATE OF dp SKIP LOCKED",
    [quote.pickup_lon, quote.pickup_lat]
   );
   const driver = driverResult.rows[0] as { user_id: string } | undefined;
   if (!driver) {
    await client.query("ROLLBACK");
    return reply.code(409).send({ error: { code: "NO_DRIVER_AVAILABLE", message: "No verified available driver was found nearby. No ride was booked; please try again shortly." } });
   }

   const rideId = (await client.query("SELECT gen_random_uuid() AS id")).rows[0].id as string;
   const pickupPin = String(randomInt(0, 10000)).padStart(4, "0");
   const pickupPinHash = createHmac("sha256", pinSecret).update(rideId + ":" + pickupPin).digest("hex");
   const rideResult = await client.query(
    "INSERT INTO rides (id, rider_id, driver_id, fare_quote_id, status, version, pickup, dropoff, currency, final_amount_minor, start_pin_hash, assigned_at) VALUES ($1,$2,$3,$4,'DRIVER_ASSIGNED',1,ST_SetSRID(ST_MakePoint($5,$6),4326)::geography,ST_SetSRID(ST_MakePoint($7,$8),4326)::geography,$9,$10,$11,now()) RETURNING id, status, version, requested_at, assigned_at",
    [rideId, account.id, driver.user_id, quote.id, quote.pickup_lon, quote.pickup_lat, quote.dropoff_lon, quote.dropoff_lat, quote.currency, quote.amount_minor, pickupPinHash]
   );
   const ride = rideResult.rows[0] as { id: string; status: RideStatus; version: number; requested_at: Date; assigned_at: Date };
   await client.query("UPDATE driver_profiles SET is_available = false, updated_at = now() WHERE user_id = $1", [driver.user_id]);
   await client.query("INSERT INTO ride_events (ride_id, version, actor_user_id, event_type, payload) VALUES ($1,1,$2,'DRIVER_ASSIGNED',jsonb_build_object('driverId',$3::text))", [ride.id, account.id, driver.user_id]);
   const responseBody = {
    id: ride.id, status: ride.status, version: ride.version,
    driverAssigned: true, pickupPin, fare: { amountMinor: Number(quote.amount_minor), currency: quote.currency },
    requestedAt: ride.requested_at, assignedAt: ride.assigned_at
   };
   await client.query("UPDATE idempotency_records SET response_status = 201, response_body = $3::jsonb WHERE principal_id = $1 AND idempotency_key = $2", [account.id, parsed.data.idempotencyKey, JSON.stringify(responseBody)]);
   await client.query("COMMIT");
   return reply.code(201).send(responseBody);
  } catch (error) {
   await client.query("ROLLBACK").catch(() => undefined);
   request.log.error({ requestId: request.id, err: error }, "Ride request transaction failed");
   return reply.code(503).send({ error: { code: "RIDE_REQUEST_FAILED", message: "The ride could not be booked safely. Please retry with the same idempotency key." } });
  } finally {
   client.release();
  }
 });

 app.post("/v1/rides/:rideId/cancel", async (request, reply) => {
  const account = await currentAccount(request, reply, deps.pool, deps.verifier);
  if (!account) return;
  if (account.role !== "CUSTOMER" && account.role !== "DRIVER" && account.role !== "ADMIN") {
   return reply.code(403).send({ error: { code: "ROLE_FORBIDDEN", message: "This account cannot cancel rides." } });
  }
  const params = z.object({ rideId: z.string().uuid() }).safeParse(request.params);
  if (!params.success) return reply.code(400).send({ error: { code: "INVALID_RIDE_ID", message: "A valid ride ID is required." } });
  const pool = deps.pool!;
  const client = await pool.connect();
  try {
   await client.query("BEGIN");
   const selected = await client.query("SELECT id, rider_id, driver_id, status, version FROM rides WHERE id = $1 FOR UPDATE", [params.data.rideId]);
   const ride = selected.rows[0] as { id: string; rider_id: string; driver_id: string | null; status: RideStatus; version: number } | undefined;
   if (!ride) {
    await client.query("ROLLBACK");
    return reply.code(404).send({ error: { code: "RIDE_NOT_FOUND", message: "Ride not found." } });
   }
   if ((account.role === "CUSTOMER" && ride.rider_id !== account.id) ||
       (account.role === "DRIVER" && ride.driver_id !== account.id)) {
    await client.query("ROLLBACK");
    return reply.code(403).send({ error: { code: "RIDE_FORBIDDEN", message: "This ride does not belong to this account." } });
   }
   try { assertTransition(ride.status, "CANCELLED"); }
   catch {
    await client.query("ROLLBACK");
    return reply.code(409).send({ error: { code: "RIDE_NOT_CANCELLABLE", message: "This ride can no longer be cancelled in its current state." } });
   }
   const nextVersion = ride.version + 1;
   await client.query("UPDATE rides SET status = 'CANCELLED', version = $2, cancelled_at = now(), updated_at = now() WHERE id = $1", [ride.id, nextVersion]);
   if (ride.driver_id) {
    await client.query("UPDATE driver_profiles SET is_available = true, updated_at = now() WHERE user_id = $1 AND verification_status = 'VERIFIED'", [ride.driver_id]);
   }
   await client.query("INSERT INTO ride_events (ride_id, version, actor_user_id, event_type) VALUES ($1,$2,$3,'CANCELLED')", [ride.id, nextVersion, account.id]);
   await client.query("COMMIT");
   return { id: ride.id, status: "CANCELLED", version: nextVersion };
  } catch (error) {
   await client.query("ROLLBACK").catch(() => undefined);
   request.log.error({ requestId: request.id, err: error }, "Ride cancellation transaction failed");
   return reply.code(503).send({ error: { code: "CANCELLATION_FAILED", message: "Cancellation could not be confirmed. Please refresh ride status." } });
  } finally {
   client.release();
  }
 });

 app.get("/v1/rides/:rideId", async (request, reply) => {
  const account = await currentAccount(request, reply, deps.pool, deps.verifier);
  if (!account) return;
  const params = z.object({ rideId: z.string().uuid() }).safeParse(request.params);
  if (!params.success) return reply.code(400).send({ error: { code: "INVALID_RIDE_ID", message: "A valid ride ID is required." } });
  if (!deps.pool) return reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Ride service is unavailable." } });
  const result = await deps.pool.query(
   "SELECT id, rider_id, driver_id, status, version, currency, final_amount_minor, requested_at, assigned_at, started_at, completed_at, cancelled_at FROM rides WHERE id = $1 LIMIT 1",
   [params.data.rideId]
  );
  const ride = result.rows[0] as { id: string; rider_id: string; driver_id: string | null; status: string; version: number; currency: string; final_amount_minor: string | number | null; requested_at: Date; assigned_at: Date | null; started_at: Date | null; completed_at: Date | null; cancelled_at: Date | null } | undefined;
  if (!ride) return reply.code(404).send({ error: { code: "RIDE_NOT_FOUND", message: "Ride not found." } });
  if (account.role !== "ADMIN" && ride.rider_id !== account.id && ride.driver_id !== account.id) {
   return reply.code(403).send({ error: { code: "RIDE_FORBIDDEN", message: "This ride does not belong to this account." } });
  }
  return { id: ride.id, status: ride.status, version: ride.version,
   fare: ride.final_amount_minor === null ? null : { amountMinor: Number(ride.final_amount_minor), currency: ride.currency },
   requestedAt: ride.requested_at, assignedAt: ride.assigned_at, startedAt: ride.started_at,
   completedAt: ride.completed_at, cancelledAt: ride.cancelled_at };
 });

 app.post("/v1/rides/:rideId/status", async (request, reply) => {
  const account = await currentAccount(request, reply, deps.pool, deps.verifier);
  if (!account) return;
  if (account.role !== "DRIVER") return reply.code(403).send({ error: { code: "ROLE_FORBIDDEN", message: "Only the assigned driver can update ride progress." } });
  const params = z.object({ rideId: z.string().uuid() }).safeParse(request.params);
  const body = z.object({
   status: z.enum(["DRIVER_ARRIVING", "DRIVER_ARRIVED", "IN_PROGRESS", "COMPLETED"]),
   pickupPin: z.string().optional()
  }).strict().safeParse(request.body);
  if (!params.success || !body.success) return reply.code(400).send({ error: { code: "INVALID_REQUEST", message: "A valid ride ID and status are required." } });
  if (!deps.pool) return reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Ride service is unavailable." } });
  const client = await deps.pool.connect();
  try {
   await client.query("BEGIN");
   const selected = await client.query("SELECT id, driver_id, status, version, start_pin_hash FROM rides WHERE id = $1 FOR UPDATE", [params.data.rideId]);
   const ride = selected.rows[0] as { id: string; driver_id: string | null; status: RideStatus; version: number; start_pin_hash: string | null } | undefined;
   if (!ride) { await client.query("ROLLBACK"); return reply.code(404).send({ error: { code: "RIDE_NOT_FOUND", message: "Ride not found." } }); }
   if (ride.driver_id !== account.id) { await client.query("ROLLBACK"); return reply.code(403).send({ error: { code: "RIDE_FORBIDDEN", message: "Only the assigned driver can update this ride." } }); }
   if (ride.status === body.data.status) { await client.query("ROLLBACK"); return { id: ride.id, status: ride.status, version: ride.version }; }
   try { assertTransition(ride.status, body.data.status); }
   catch { await client.query("ROLLBACK"); return reply.code(409).send({ error: { code: "INVALID_RIDE_TRANSITION", message: "This ride cannot move to the requested status." } }); }
   if (body.data.status === "IN_PROGRESS") {
    const secret = process.env.RIDE_PIN_SECRET?.trim();
    if (!secret || secret.length < 32 || !ride.start_pin_hash || !body.data.pickupPin || !/^\d{4}$/.test(body.data.pickupPin)) {
     await client.query("ROLLBACK");
     return reply.code(400).send({ error: { code: "PICKUP_PIN_REQUIRED", message: "A valid four-digit customer pickup PIN is required before the trip starts." } });
    }
    const expected = Buffer.from(ride.start_pin_hash, "hex");
    const actual = createHmac("sha256", secret).update(ride.id + ":" + body.data.pickupPin).digest();
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
     await client.query("ROLLBACK");
     return reply.code(400).send({ error: { code: "INVALID_PICKUP_PIN", message: "The pickup PIN is incorrect." } });
    }
   }
   const version = ride.version + 1;
   const timestampColumn = body.data.status === "IN_PROGRESS" ? "started_at" : body.data.status === "COMPLETED" ? "completed_at" : null;
   if (timestampColumn) await client.query("UPDATE rides SET status = $2, version = $3, " + timestampColumn + " = now(), updated_at = now() WHERE id = $1", [ride.id, body.data.status, version]);
   else await client.query("UPDATE rides SET status = $2, version = $3, updated_at = now() WHERE id = $1", [ride.id, body.data.status, version]);
   await client.query("INSERT INTO ride_events (ride_id, version, actor_user_id, event_type) VALUES ($1,$2,$3,$4)", [ride.id, version, account.id, body.data.status]);
   if (body.data.status === "COMPLETED") await client.query("UPDATE driver_profiles SET is_available = true, updated_at = now() WHERE user_id = $1 AND verification_status = 'VERIFIED'", [account.id]);
   await client.query("COMMIT");
   return { id: ride.id, status: body.data.status, version };
  } catch (error) {
   await client.query("ROLLBACK").catch(() => undefined);
   request.log.error({ requestId: request.id, err: error }, "Ride status update failed");
   return reply.code(503).send({ error: { code: "RIDE_UPDATE_FAILED", message: "Ride status could not be updated safely." } });
  } finally { client.release(); }
 });

}
