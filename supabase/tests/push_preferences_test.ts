import { optionalPushEnabled } from "../functions/push-notifications/preferences.ts";

Deno.test("mandatory events survive all optional push opt-outs", () => {
  const off = { match_reminders: false, booking_reminders: false, chat_messages: false, offers: false, news: false };
  for (const type of ["booking_confirmation", "booking_cancellation", "payment_confirmed", "payment_failed", "refund_requested", "refund_completed", "match_confirmed", "match_cancelled"]) {
    if (!optionalPushEnabled(type, off)) throw Error(type);
  }
  for (const type of ["match_reminder", "booking_reminder", "message", "offer", "news"]) {
    if (optionalPushEnabled(type, off)) throw Error(type);
  }
});
Deno.test("defaults preserve reminders and require marketing opt-in", () => {
  if (!optionalPushEnabled("booking_reminder", null)) throw Error("reminder default");
  if (optionalPushEnabled("offer", null) || optionalPushEnabled("news", null)) throw Error("marketing default");
  if (!optionalPushEnabled("offer", { offers: true })) throw Error("opt-in ignored");
});
