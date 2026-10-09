import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";

export type AuthenticatedPrincipal = {
 subject: string;
 roles: string[];
 claims: JWTPayload;
};

export class AuthenticationConfigurationError extends Error {
 constructor(message: string) { super(message); this.name = "AuthenticationConfigurationError"; }
}

/**
 * Verifies access tokens issued by the configured identity provider.
 * No local/dev bypass is provided. Until issuer, audience and JWKS are configured,
 * protected endpoints must remain unavailable rather than trusting client-supplied roles.
 */
export function createAccessTokenVerifier(env: NodeJS.ProcessEnv = process.env) {
 const jwksUrl = env.AUTH_JWKS_URL?.trim();
 const issuer = env.AUTH_ISSUER?.trim();
 const audience = env.AUTH_AUDIENCE?.trim();
 if (!jwksUrl || !issuer || !audience) {
  throw new AuthenticationConfigurationError("AUTH_JWKS_URL, AUTH_ISSUER and AUTH_AUDIENCE must be configured.");
 }
 let url: URL;
 try { url = new URL(jwksUrl); }
 catch { throw new AuthenticationConfigurationError("AUTH_JWKS_URL must be an absolute URL."); }
 if (url.protocol !== "https:" && env.NODE_ENV === "production") {
  throw new AuthenticationConfigurationError("Production JWKS URL must use HTTPS.");
 }
 const jwks = createRemoteJWKSet(url);
 return async (token: string): Promise<AuthenticatedPrincipal> => {
  const verified = await jwtVerify(token, jwks, { issuer, audience, algorithms: ["RS256", "ES256"] });
  const subject = verified.payload.sub;
  if (!subject) throw new Error("Access token has no subject.");
  const rolesClaim = verified.payload.roles;
  const roles = Array.isArray(rolesClaim) ? rolesClaim.filter((value): value is string => typeof value === "string") : [];
  return { subject, roles, claims: verified.payload };
 };
}
