import test from "node:test";
import assert from "node:assert/strict";
import { AuthenticationConfigurationError, createAccessTokenVerifier } from "./jwt.js";

test("refuses to configure access-token verification without identity provider settings", () => {
 assert.throws(
  () => createAccessTokenVerifier({}),
  (error: unknown) => error instanceof AuthenticationConfigurationError
 );
});
