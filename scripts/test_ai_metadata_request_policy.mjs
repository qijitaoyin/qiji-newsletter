import assert from "node:assert/strict";
import { createResilientRequester, parseRetryAfterMs } from "./ai_metadata_request_policy.mjs";

assert.equal(parseRetryAfterMs("2"), 2000);
assert.equal(parseRetryAfterMs("invalid"), 0);

const responses = [
  new Response("rate limited", { status: 429, headers: { "retry-after": "0" } }),
  new Response("temporary", { status: 503 }),
  new Response("ok", { status: 200 })
];
const waits = [];
const retries = [];
const requester = createResilientRequester({
  fetchImpl: async () => responses.shift(),
  timeoutMs: 1000,
  minIntervalMs: 0,
  maxAttempts: 4,
  baseDelayMs: 10,
  sleepImpl: async (ms) => waits.push(ms),
  onRetry: (event) => retries.push(event)
});

const response = await requester("https://example.invalid", {}, { label: "fixture" });
assert.equal(response.status, 200);
assert.equal(retries.length, 2);
assert.deepEqual(retries.map((item) => item.status), [429, 503]);
assert.deepEqual(waits, [0, 20]);

let attempts = 0;
const failingRequester = createResilientRequester({
  fetchImpl: async () => {
    attempts += 1;
    return new Response("rate limited", { status: 429 });
  },
  timeoutMs: 1000,
  minIntervalMs: 0,
  maxAttempts: 3,
  baseDelayMs: 1,
  sleepImpl: async () => {}
});
const failedResponse = await failingRequester("https://example.invalid");
assert.equal(failedResponse.status, 429);
assert.equal(attempts, 3);

console.log("AI metadata retry policy tests passed.");
