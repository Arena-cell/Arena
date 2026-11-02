// Transactional booking/payment events are intentionally absent: always send.
export function optionalPushField(type: string): string | null {
  return ({ match_reminder: "match_reminders", booking_reminder: "booking_reminders",
    message: "chat_messages", offer: "offers", promotion: "offers", news: "news" } as Record<string, string>)[type] ?? null;
}

export function optionalPushEnabled(type: string, preferences: Record<string, unknown> | null): boolean {
  const field = optionalPushField(type);
  if (!field) return true;
  return typeof preferences?.[field] === "boolean"
    ? preferences[field] === true : !["offers", "news"].includes(field);
}
