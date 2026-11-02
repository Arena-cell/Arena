import { createClient } from "https://esm.sh/@supabase/supabase-js@2.110.0";

const json = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json" },
  });
export async function arenaSchedulerHandler(
  request: Request,
): Promise<Response> {
  if (request.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }
  const secret = Deno.env.get("ARENA_SCHEDULER_SECRET");
  if (!secret || request.headers.get("Authorization") !== `Bearer ${secret}`) {
    return json({ error: "UNAUTHORIZED" }, 401);
  }
  const url = Deno.env.get("SUPABASE_URL");
  if (url !== "https://gtcrijikfaglqcwqozel.supabase.co") {
    return json({ error: "STAGING_ONLY" }, 403);
  }
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key) return json({ error: "SERVER_NOT_CONFIGURED" }, 503);
  const db = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const { data: events, error: eventError } = await db.rpc(
      "process_arena_scheduled_events",
    );
    if (eventError) throw eventError;
    const pushSecret = Deno.env.get("PUSH_DISPATCH_SECRET");
    if (!pushSecret || !Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")) {
      return json({ events, push: "NOT_CONFIGURED" }, 503);
    }
    const { data: batch, error } = await db.rpc("claim_arena_push_batch", {
      p_limit: 3,
    });
    if (error) throw error;
    let processed = 0;
    for (const notification of batch ?? []) {
      let status = "failed";
      try {
        const response = await fetch(`${url}/functions/v1/push-notifications`, {
          method: "POST",
          headers: {
            "x-arena-push-secret": pushSecret,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ notification_id: notification.id }),
          signal: AbortSignal.timeout(45000),
        });
        const result = await response.json();
        if (response.ok) {
          const { data: activeTokens, error: tokenError } = await db.from(
            "device_tokens",
          )
            .select("id").eq(
              "user_id",
              notification.user_id,
            ).eq("is_active", true);
          if (tokenError) throw tokenError;
          const { data: deliveries, error: deliveryError } =
            activeTokens?.length
              ? await db.from(
                "notification_push_deliveries",
              ).select("status").eq("notification_id", notification.id)
                .in("device_token_id", activeTokens.map((t) => t.id))
              : { data: [], error: null };
          if (deliveryError) throw deliveryError;
          status = !activeTokens?.length
            ? "no_device"
            : deliveries?.some((d) => d.status !== "sent") ||
                deliveries?.length !== activeTokens.length
            ? "failed"
            : "sent";
        }
      } catch {
        status = "failed";
      }
      const { error: finishError } = await db.rpc("finish_arena_push", {
        p_notification: notification.id,
        p_lease: notification.lease_id,
        p_status: status,
      });
      if (finishError) throw finishError;
      processed++;
    }
    return json({ events, processed });
  } catch {
    return json({ error: "SCHEDULER_FAILED" }, 500);
  }
}
