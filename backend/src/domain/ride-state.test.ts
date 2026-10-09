import test from "node:test";
import assert from "node:assert/strict";
import { assertTransition, canTransition, isTerminal } from "./ride-state.js";
test("allows the expected booking lifecycle", () => {
 const path = ["REQUESTED","SEARCHING","DRIVER_ASSIGNED","DRIVER_ARRIVING","DRIVER_ARRIVED","IN_PROGRESS","COMPLETED"] as const;
 for (let i = 1; i < path.length; i += 1) assert.equal(canTransition(path[i - 1]!, path[i]!), true);
});
test("rejects invalid jumps and terminal resurrection", () => {
 assert.equal(canTransition("SEARCHING","IN_PROGRESS"), false);
 assert.equal(canTransition("COMPLETED","CANCELLED"), false);
 assert.equal(canTransition("CANCELLED","DRIVER_ASSIGNED"), false);
 assert.throws(() => assertTransition("COMPLETED","SEARCHING"));
});
test("recognizes terminal outcomes", () => {
 for (const status of ["COMPLETED","CANCELLED","EXPIRED","NO_DRIVER_FOUND","FAILED"] as const) assert.equal(isTerminal(status), true);
});
