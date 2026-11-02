import { arenaSchedulerHandler } from "../functions/arena-scheduler/handler.ts";
import { pushNotificationHandler } from "../functions/push-notifications/handler.ts";

function equal(actual: unknown, expected: unknown) {
  if (actual !== expected) {
    throw new Error(`Expected ${expected}, received ${actual}`);
  }
}
// No provider/Firebase network requests. Exercise the real request handlers.
Deno.test("Scheduler rejects unauthenticated and wrong-secret requests", async () => {
  Deno.env.delete("ARENA_SCHEDULER_SECRET");
  equal(
    (await arenaSchedulerHandler(
      new Request("http://localhost", { method: "POST" }),
    )).status,
    401,
  );
  Deno.env.set("ARENA_SCHEDULER_SECRET", "local-test-secret");
  equal(
    (await arenaSchedulerHandler(
      new Request("http://localhost", {
        method: "POST",
        headers: { Authorization: "Bearer wrong" },
      }),
    )).status,
    401,
  );
});
Deno.test("Scheduler refuses Production even with a valid job secret", async () => {
  Deno.env.set("SUPABASE_URL", "https://mbgqnlbuslrgamkzdqpd.supabase.co");
  equal(
    (await arenaSchedulerHandler(
      new Request("http://localhost", {
        method: "POST",
        headers: { Authorization: "Bearer local-test-secret" },
      }),
    )).status,
    403,
  );
});
Deno.test("Scheduler missing server configuration fails closed", async () => {
  Deno.env.set("SUPABASE_URL", "https://gtcrijikfaglqcwqozel.supabase.co");
  Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
  equal(
    (await arenaSchedulerHandler(
      new Request("http://localhost", {
        method: "POST",
        headers: { Authorization: "Bearer local-test-secret" },
      }),
    )).status,
    503,
  );
});
Deno.test("Push rejects unauthenticated and ordinary user requests", async () => {
  Deno.env.delete("PUSH_DISPATCH_SECRET");
  equal(
    (await pushNotificationHandler(
      new Request("http://localhost", { method: "POST" }),
    )).status,
    401,
  );
  Deno.env.set("PUSH_DISPATCH_SECRET", "local-test-push-secret");
  equal(
    (await pushNotificationHandler(
      new Request("http://localhost", {
        method: "POST",
        headers: { Authorization: "Bearer ordinary-user" },
      }),
    )).status,
    401,
  );
});
Deno.test("Push refuses Production and missing Firebase configuration", async () => {
  const request = () =>
    new Request("http://localhost", {
      method: "POST",
      headers: { "x-arena-push-secret": "local-test-push-secret" },
    });
  Deno.env.set("SUPABASE_URL", "https://mbgqnlbuslrgamkzdqpd.supabase.co");
  equal((await pushNotificationHandler(request())).status, 403);
  Deno.env.set("SUPABASE_URL", "https://gtcrijikfaglqcwqozel.supabase.co");
  Deno.env.delete("FIREBASE_SERVICE_ACCOUNT_JSON");
  equal((await pushNotificationHandler(request())).status, 503);
});
