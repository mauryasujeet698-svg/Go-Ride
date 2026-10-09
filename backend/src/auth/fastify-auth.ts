import type { FastifyReply, FastifyRequest } from "fastify";
import { createAccessTokenVerifier, type AuthenticatedPrincipal } from "./jwt.js";

export type AccessTokenVerifier = ReturnType<typeof createAccessTokenVerifier>;

export function readBearerToken(request: FastifyRequest): string | null {
 const header = request.headers.authorization;
 if (!header) return null;
 const match = /^Bearer ([^\s]+)$/i.exec(header);
 return match?.[1] ?? null;
}

export async function verifyRequestPrincipal(
 request: FastifyRequest,
 reply: FastifyReply,
 verifier: AccessTokenVerifier | null
): Promise<AuthenticatedPrincipal | null> {
 if (!verifier) {
  await reply.code(503).send({ error: { code: "AUTH_NOT_CONFIGURED", message: "Authentication provider is not configured." } });
  return null;
 }
 const token = readBearerToken(request);
 if (!token) {
  await reply.code(401).send({ error: { code: "UNAUTHENTICATED", message: "A valid bearer token is required." } });
  return null;
 }
 try {
  return await verifier(token);
 } catch {
  await reply.code(401).send({ error: { code: "INVALID_TOKEN", message: "The access token is invalid or expired." } });
  return null;
 }
}
