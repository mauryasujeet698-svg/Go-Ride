import test from "node:test";
import assert from "node:assert/strict";
import { readBearerToken } from "./fastify-auth.js";

test("accepts a well-formed bearer authorization header", () => {
 assert.equal(readBearerToken({ headers: { authorization: "Bearer abc.def.ghi" } } as never), "abc.def.ghi");
});
test("rejects missing, malformed and multi-part headers", () => {
 assert.equal(readBearerToken({ headers: {} } as never), null);
 assert.equal(readBearerToken({ headers: { authorization: "Basic abc" } } as never), null);
 assert.equal(readBearerToken({ headers: { authorization: "Bearer one two" } } as never), null);
});
