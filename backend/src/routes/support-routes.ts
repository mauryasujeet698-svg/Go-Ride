import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type pg from "pg";
import { z } from "zod";
import { verifyRequestPrincipal, type AccessTokenVerifier } from "../auth/fastify-auth.js";
import type { FeatureConfig } from "../config/features.js";

type Dependencies = { pool: pg.Pool | undefined; verifier: AccessTokenVerifier | null; features: FeatureConfig };
type Account = { id: string; role: string; status: string };

async function accountFor(request: FastifyRequest, reply: FastifyReply, deps: Dependencies): Promise<Account | null> {
 const principal = await verifyRequestPrincipal(request, reply, deps.verifier);
 if (!principal) return null;
 if (!deps.pool) { await reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Support service is unavailable." } }); return null; }
 if (typeof principal.claims.iss !== "string") { await reply.code(401).send({ error: { code: "INVALID_TOKEN", message: "The access token has no issuer." } }); return null; }
 const result = await deps.pool.query("SELECT id, role, status FROM app_users WHERE auth_issuer = $1 AND auth_subject = $2 LIMIT 1", [principal.claims.iss, principal.subject]);
 const user = result.rows[0] as Account | undefined;
 if (!user || user.status !== "ACTIVE") { await reply.code(403).send({ error: { code: "ACCOUNT_UNAVAILABLE", message: "The account is not active." } }); return null; }
 return user;
}

export async function registerSupportRoutes(app: FastifyInstance, deps: Dependencies): Promise<void> {
 app.post("/v1/support/cases", async (request, reply) => {
  const account = await accountFor(request, reply, deps);
  if (!account) return;
  const allowed = account.role === "CUSTOMER" ? deps.features.support.customer
   : account.role === "DRIVER" ? deps.features.support.driver : false;
  if (!allowed) return reply.code(503).send({ error: { code: "SUPPORT_UNAVAILABLE", message: "Support intake is not enabled for this account type." } });
  const body = z.object({
   category: z.enum(["RIDE_ISSUE", "PAYMENT", "DRIVER_BEHAVIOUR", "SAFETY", "ACCOUNT", "OTHER"]),
   description: z.string().trim().min(10).max(4000),
   rideId: z.string().uuid().optional()
  }).strict().safeParse(request.body);
  if (!body.success) return reply.code(400).send({ error: { code: "INVALID_REQUEST", message: "A valid category and description are required." } });
  if (!deps.pool) return reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Support service is unavailable." } });
  const client = await deps.pool.connect();
  try {
   await client.query("BEGIN");
   if (body.data.rideId) {
    const ride = await client.query("SELECT id, rider_id, driver_id FROM rides WHERE id = $1 FOR SHARE", [body.data.rideId]);
    const row = ride.rows[0] as { id: string; rider_id: string; driver_id: string | null } | undefined;
    if (!row || (account.role === "CUSTOMER" && row.rider_id !== account.id) || (account.role === "DRIVER" && row.driver_id !== account.id)) {
     await client.query("ROLLBACK");
     return reply.code(404).send({ error: { code: "RIDE_NOT_FOUND", message: "The referenced ride could not be found for this account." } });
    }
   }
   const inserted = await client.query(
    "INSERT INTO support_cases (requester_id, ride_id, category, description) VALUES ($1,$2,$3,$4) RETURNING id, status, priority, created_at",
    [account.id, body.data.rideId ?? null, body.data.category, body.data.description]
   );
   const item = inserted.rows[0] as { id: string; status: string; priority: string; created_at: Date };
   await client.query("INSERT INTO audit_events (actor_user_id, action, target_type, target_id, reason, request_id) VALUES ($1,'SUPPORT_CASE_CREATED','support_case',$2,'Requester opened a support case',$3)", [account.id, item.id, request.id]);
   await client.query("COMMIT");
   return reply.code(201).send({ id: item.id, status: item.status, priority: item.priority, createdAt: item.created_at });
  } catch (error) {
   await client.query("ROLLBACK").catch(() => undefined);
   request.log.error({ requestId: request.id }, "Support case creation failed");
   return reply.code(503).send({ error: { code: "SUPPORT_CREATE_FAILED", message: "The support case could not be saved." } });
  } finally { client.release(); }
 });

 app.get("/v1/admin/support/cases", async (request, reply) => {
  const account = await accountFor(request, reply, deps);
  if (!account) return;
  if (account.role !== "ADMIN" && account.role !== "SUPPORT") return reply.code(403).send({ error: { code: "ROLE_FORBIDDEN", message: "Support or admin access is required." } });
  if (!deps.pool) return reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Support service is unavailable." } });
  const query = z.object({
   status: z.enum(["OPEN", "ASSIGNED", "WAITING", "RESOLVED", "CLOSED"]).optional(),
   limit: z.coerce.number().int().min(1).max(100).default(50)
  }).safeParse(request.query);
  if (!query.success) return reply.code(400).send({ error: { code: "INVALID_QUERY", message: "Invalid support case filters." } });
  const result = await deps.pool.query(
   "SELECT id, requester_id, ride_id, category, description, status, priority, assigned_to, created_at, updated_at FROM support_cases WHERE ($1::text IS NULL OR status = $1) ORDER BY CASE priority WHEN 'URGENT' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, created_at ASC LIMIT $2",
   [query.data.status ?? null, query.data.limit]
  );
  return { items: result.rows, count: result.rowCount ?? result.rows.length };
 });

 app.patch("/v1/admin/support/cases/:caseId", async (request, reply) => {
  const account = await accountFor(request, reply, deps);
  if (!account) return;
  if (account.role !== "ADMIN" && account.role !== "SUPPORT") return reply.code(403).send({ error: { code: "ROLE_FORBIDDEN", message: "Support or admin access is required." } });
  if (!deps.pool) return reply.code(503).send({ error: { code: "DATABASE_NOT_CONFIGURED", message: "Support service is unavailable." } });
  const params = z.object({ caseId: z.string().uuid() }).safeParse(request.params);
  const body = z.object({
   status: z.enum(["OPEN", "ASSIGNED", "WAITING", "RESOLVED", "CLOSED"]),
   priority: z.enum(["LOW", "NORMAL", "HIGH", "URGENT"]).optional(),
   assignedTo: z.string().uuid().nullable().optional(),
   reason: z.string().trim().min(8).max(500)
  }).strict().safeParse(request.body);
  if (!params.success || !body.success) return reply.code(400).send({ error: { code: "INVALID_REQUEST", message: "Case ID, valid status and audit reason are required." } });
  const client = await deps.pool.connect();
  try {
   await client.query("BEGIN");
   const current = await client.query("SELECT id, status FROM support_cases WHERE id = $1 FOR UPDATE", [params.data.caseId]);
   if (current.rowCount === 0) { await client.query("ROLLBACK"); return reply.code(404).send({ error: { code: "CASE_NOT_FOUND", message: "Support case not found." } }); }
   if (body.data.assignedTo) {
    const assignee = await client.query("SELECT id FROM app_users WHERE id = $1 AND status = 'ACTIVE' AND role IN ('ADMIN','SUPPORT')", [body.data.assignedTo]);
    if (assignee.rowCount === 0) { await client.query("ROLLBACK"); return reply.code(400).send({ error: { code: "INVALID_ASSIGNEE", message: "Cases can only be assigned to active support/admin accounts." } }); }
   }
   const updated = await client.query(
    "UPDATE support_cases SET status = $2, priority = COALESCE($3, priority), assigned_to = CASE WHEN $4::boolean THEN $5::uuid ELSE assigned_to END, updated_at = now(), resolved_at = CASE WHEN $2 IN ('RESOLVED','CLOSED') THEN COALESCE(resolved_at,now()) ELSE NULL END WHERE id = $1 RETURNING id, status, priority, assigned_to, updated_at",
    [params.data.caseId, body.data.status, body.data.priority ?? null, body.data.assignedTo !== undefined, body.data.assignedTo ?? null]
   );
   await client.query("INSERT INTO audit_events (actor_user_id, action, target_type, target_id, reason, request_id, metadata) VALUES ($1,'SUPPORT_CASE_UPDATED','support_case',$2,$3,$4,$5::jsonb)", [account.id, params.data.caseId, body.data.reason, request.id, JSON.stringify({ status: body.data.status, priority: body.data.priority ?? null, assignedTo: body.data.assignedTo ?? null })]);
   await client.query("COMMIT");
   return updated.rows[0];
  } catch (error) {
   await client.query("ROLLBACK").catch(() => undefined);
   request.log.error({ requestId: request.id }, "Support case update failed");
   return reply.code(503).send({ error: { code: "SUPPORT_UPDATE_FAILED", message: "The support case could not be updated." } });
  } finally { client.release(); }
 });
}
