import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const jsonHeaders = { 'Content-Type': 'application/json' };

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
  try {
    const dispatchSecret = Deno.env.get('PUSH_DISPATCH_SECRET');
    const suppliedSecret = request.headers.get('x-arena-push-secret');
    if (!dispatchSecret || suppliedSecret !== dispatchSecret) {
      return json({ error: 'UNAUTHORIZED' }, 401);
    }
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const rawServiceAccount = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!supabaseUrl || !serviceRoleKey || !rawServiceAccount) {
      return json({ error: 'PUSH_NOT_CONFIGURED' }, 503);
    }
    const body = await request.json().catch(() => ({}));
    const notificationId = `${body.notification_id ?? body.record?.id ?? ''}`;
    if (!/^[0-9a-f-]{36}$/i.test(notificationId)) {
      return json({ error: 'INVALID_NOTIFICATION_ID' }, 400);
    }
    const serviceAccount = JSON.parse(rawServiceAccount) as ServiceAccount;
    if (
      !serviceAccount.client_email ||
      !serviceAccount.private_key ||
      !serviceAccount.project_id
    ) {
      return json({ error: 'INVALID_FIREBASE_CONFIGURATION' }, 503);
    }
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: notification, error: notificationError } = await supabase
      .from('notifications')
      .select(
        'id,user_id,type,title,title_ar,title_en,body,body_ar,body_en,data,event_key,read_at',
      )
      .eq('id', notificationId)
      .maybeSingle();
    if (notificationError) throw notificationError;
    if (!notification) return json({ error: 'NOTIFICATION_NOT_FOUND' }, 404);

    const { data: tokens, error: tokenError } = await supabase
      .from('device_tokens')
      .select('id,token,platform,locale')
      .eq('user_id', notification.user_id);
    if (tokenError) throw tokenError;
    if (!tokens?.length) return json({ sent: 0, failed: 0, skipped: 0 });

    const accessToken = await firebaseAccessToken(serviceAccount);
    const { count: unreadCount } = await supabase
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', notification.user_id)
      .is('read_at', null);

    let sent = 0;
    let failed = 0;
    let skipped = 0;
    for (const token of tokens) {
      const { data: claimedDelivery, error: claimError } = await supabase
        .rpc('claim_notification_push_delivery', {
          p_notification_id: notification.id,
          p_device_token_id: token.id,
        })
        .maybeSingle();
      if (claimError) throw claimError;
      const delivery = claimedDelivery as {
        delivery_id: string;
        delivery_attempt_count: number;
      } | null;
      if (!delivery) {
        skipped += 1;
        continue;
      }
      const locale = token.locale === 'ar' ? 'ar' : 'en';
      const title =
        notification[locale === 'ar' ? 'title_ar' : 'title_en'] ||
        (locale === 'ar' ? 'أرينا' : 'Arena');
      const messageBody =
        notification[locale === 'ar' ? 'body_ar' : 'body_en'] ||
        '';
      const payloadData = stringifyData({
        ...(notification.data ?? {}),
        type: notification.type,
        notification_id: notification.id,
        event_key: notification.event_key ?? '',
      });
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(serviceAccount.project_id)}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: token.token,
              notification: { title, body: messageBody },
              data: payloadData,
              android: {
                priority: 'high',
                notification: {
                  click_action: 'FLUTTER_NOTIFICATION_CLICK',
                },
              },
              apns: {
                headers: { 'apns-priority': '10' },
                payload: {
                  aps: {
                    sound: 'default',
                    badge: unreadCount ?? 1,
                    'content-available': 1,
                  },
                },
              },
            },
          }),
        },
      );
      const result = await response.json().catch(() => ({}));
      if (response.ok) {
        sent += 1;
        await supabase
          .from('notification_push_deliveries')
          .update({
            status: 'sent',
            provider_message_id: `${result.name ?? ''}`.slice(0, 500),
            last_error_code: null,
            updated_at: new Date().toISOString(),
          })
          .eq('id', delivery.delivery_id);
      } else {
        failed += 1;
        const providerCode = result.error?.details?.find(
          (detail: Record<string, unknown>) => detail.errorCode,
        )?.errorCode;
        const errorCode = `${providerCode ?? result.error?.status ?? 'FCM_ERROR'}`
          .slice(0, 80);
        await supabase
          .from('notification_push_deliveries')
          .update({
            status: 'failed',
            last_error_code: errorCode,
            updated_at: new Date().toISOString(),
          })
          .eq('id', delivery.delivery_id);
        if (
          errorCode === 'UNREGISTERED' ||
          errorCode === 'INVALID_ARGUMENT'
        ) {
          await supabase.from('device_tokens').delete().eq('id', token.id);
        }
      }
    }
    return json({ sent, failed, skipped });
  } catch (error) {
    console.error(
      'push_dispatch_failed',
      error instanceof Error ? error.name : 'unknown_error',
    );
    return json({ error: 'PUSH_DISPATCH_FAILED' }, 500);
  }
});

async function firebaseAccessToken(serviceAccount: ServiceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64Url(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemBytes(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );
  const assertion = `${signingInput}.${base64UrlBytes(new Uint8Array(signature))}`;
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const tokenBody = await tokenResponse.json();
  if (!tokenResponse.ok || !tokenBody.access_token) {
    throw new Error('firebase_oauth_failed');
  }
  return `${tokenBody.access_token}`;
}

function pemBytes(value: string) {
  const binary = atob(
    value
      .replace('-----BEGIN PRIVATE KEY-----', '')
      .replace('-----END PRIVATE KEY-----', '')
      .replace(/\s/g, ''),
  );
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64Url(value: string) {
  return base64UrlBytes(new TextEncoder().encode(value));
}

function base64UrlBytes(value: Uint8Array) {
  let binary = '';
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function stringifyData(data: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(data).map(([key, value]) => [
      key,
      typeof value === 'string' ? value : JSON.stringify(value),
    ]),
  );
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}
