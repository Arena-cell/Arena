// Transport fakes exist only in this test module; no simulated sends are deployed.
import { pushNotificationHandler } from "../functions/push-notifications/handler.ts";

Deno.test("FCM invalid-token handling retains audit and private push payload", async () => {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const bytes = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  const pem = "-----BEGIN PRIVATE KEY-----\n" +
    btoa(String.fromCharCode(...bytes)) + "\n-----END PRIVATE KEY-----";
  Deno.env.set("SUPABASE_URL", "https://gtcrijikfaglqcwqozel.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "local-test-service-key");
  Deno.env.set("PUSH_DISPATCH_SECRET", "local-test-push-secret");
  Deno.env.set(
    "FIREBASE_SERVICE_ACCOUNT_JSON",
    JSON.stringify({
      client_email: "local@example.test",
      private_key: pem,
      project_id: "local-test",
    }),
  );
  const original = globalThis.fetch;
  try {
    for (const code of ["UNREGISTERED", "INVALID_ARGUMENT", "UNAVAILABLE", "SUCCESS", "OWNER_SUCCESS", "CANCEL_SUCCESS", "USER_CANCEL_SUCCESS", "OPTIONAL_SKIP"]) {
      let disabled = false;
      let fcmBody = "";
      let deliveryUpdated = false;
      let savedStatus = "";
      let nextAttempt = "";
      globalThis.fetch = (input, init) => {
        const url = String(input);
        const method = init?.method ?? "GET";
        const data = (v: unknown) =>
          Promise.resolve(
            new Response(JSON.stringify(v), {
              headers: { "Content-Type": "application/json" },
            }),
          );
        if (url.includes("/rest/v1/user_preferences")) {
          return data({ booking_reminders: false });
        }
        if (url === "https://oauth2.googleapis.com/token") {
          return data({ access_token: "local-oauth-token" });
        }
        if (url.includes("fcm.googleapis.com/")) {
          fcmBody = String(init?.body);
          if (code.endsWith("SUCCESS")) return data({name: "projects/local-test/messages/test"});
          return Promise.resolve(
            new Response(
              JSON.stringify({ error: { details: [{ errorCode: code }] } }),
              { status: 400 },
            ),
          );
        }
        if (url.includes("/rest/v1/rpc/claim_notification_push_delivery")) {
          return data([{
            delivery_id: "00000000-0000-4000-8000-000000000003",
            delivery_attempt_count: 1,
          }]);
        }
        if (
          url.includes("/rest/v1/notification_push_deliveries") &&
          method === "PATCH"
        ) {
          deliveryUpdated = true;
          const saved = JSON.parse(String(init?.body));
          savedStatus = saved.status; nextAttempt = saved.next_attempt_at ?? "";
          return Promise.resolve(new Response(null, { status: 204 }));
        }
        if (url.includes("/rest/v1/arenas")) return data({name: "ملعب النسور"});
        if (url.includes("/rest/v1/device_tokens") && method === "PATCH") {
          disabled = JSON.parse(String(init?.body)).is_active === false;
          return Promise.resolve(new Response(null, { status: 204 }));
        }
        if (url.includes("/rest/v1/device_tokens")) {
          return data([{
            id: "00000000-0000-4000-8000-000000000002",
            token: "local-test-device-token",
            platform: "android",
            locale: "en",
          }]);
        }
        if (url.includes("/rest/v1/bookings")) {
          return data({ starts_at: "2036-10-15T06:00:00Z", ends_at: "2036-10-15T07:00:00Z" });
        }
        if (url.includes("/rest/v1/notifications") && method === "HEAD") {
          return Promise.resolve(
            new Response(null, { headers: { "Content-Range": "0-0/1" } }),
          );
        }
        if (url.includes("/rest/v1/notifications")) {
          return data({
            id: "00000000-0000-4000-8000-000000000001",
            user_id: "local-user",
            type: code === "OPTIONAL_SKIP" ? "booking_reminder" : ["CANCEL_SUCCESS", "USER_CANCEL_SUCCESS"].includes(code) ? "booking_cancellation" : code === "OWNER_SUCCESS" ? "booking_confirmation" : "payment_confirmed",
            data: {
              audience: ["OWNER_SUCCESS", "CANCEL_SUCCESS"].includes(code) ? "owner" : "user",
              booking_id: "local-booking",
              arena_id: "local-arena",
              match_id: "local-match",
              amount: 20000,
              payer_name: "private-name",
            },
            body_en: "private financial text",
          });
        }
        throw Error("Unexpected test network request");
      };
      const response = await pushNotificationHandler(
        new Request("http://localhost", {
          method: "POST",
          headers: {
            "x-arena-push-secret": "local-test-push-secret",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            notification_id: "00000000-0000-4000-8000-000000000001",
          }),
        }),
      );
      if (response.status !== 200) {
        throw Error("Fake dispatch failed: " + await response.text());
      }
      if (code === "OPTIONAL_SKIP") {
        const result = await response.json();
        if (result.reason !== "USER_PREFERENCE" || fcmBody || deliveryUpdated) {
          throw Error("Opted-out reminder reached provider or delivery claim");
        }
        continue;
      }
      if (!deliveryUpdated || disabled !== (code === "UNREGISTERED") || savedStatus !== (code.endsWith("SUCCESS") ? "sent" : "failed")) {
        throw Error("Invalid FCM token/error handling");
      }
      if (!code.endsWith("SUCCESS") && Date.parse(nextAttempt) <= Date.now()) throw Error("Retry is not delayed");
      const payload = JSON.parse(fcmBody).message;
      if (code === "OWNER_SUCCESS" && payload.notification.body !== "New booking at ملعب النسور") throw Error("Owner booking text missing arena");
      if (code === "CANCEL_SUCCESS" && payload.notification.body !== "Booking cancelled at ملعب النسور — 15/10/2036 10:00–11:00 (Oman)") throw Error("Owner cancellation missing correct Oman schedule");
      if (code === "USER_CANCEL_SUCCESS" && payload.notification.body !== "Your booking was cancelled. Open the app for details.") throw Error("User cancellation type unclear");
      if (payload.android.notification.channel_id !== "arena_updates" || payload.android.notification.tag !== "00000000-0000-4000-8000-000000000001") throw Error("Missing stable channel/tag");
      if (
        fcmBody.includes("private-name") || fcmBody.includes("20000") ||
        fcmBody.includes("private financial text")
      ) throw Error("Sensitive push payload");
    }
  } finally {
    globalThis.fetch = original;
  }
});
