import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const auth = request.headers.get('Authorization');
    if (!auth) return json({ error: 'AUTH_REQUIRED' }, 401);
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    if (!supabaseUrl || !anonKey) {
      return json({ error: 'ASSISTANT_NOT_CONFIGURED' }, 503);
    }
    const supabase = createClient(
      supabaseUrl,
      anonKey,
      { global: { headers: { Authorization: auth } } },
    );
    const { data: userData } = await supabase.auth.getUser();
    const user = userData.user;
    if (!user) return json({ error: 'AUTH_REQUIRED' }, 401);
    const body = await request.json();
    const message = `${body.message ?? ''}`.trim().slice(0, 1000);
    const locale = body.locale === 'ar' ? 'ar' : 'en';
    if (!message) return json({ error: 'EMPTY_MESSAGE' }, 400);

    const { data: allowed, error: rateError } = await supabase.rpc(
      'consume_arena_assistant_rate_limit',
      { p_max_requests: 12 },
    );
    if (rateError) throw rateError;
    if (allowed !== true) return json({ error: 'RATE_LIMITED' }, 429);

    const apiKey = Deno.env.get('OPENAI_API_KEY');
    if (!apiKey) return json({ error: 'AI_NOT_CONFIGURED' }, 503);
    const extraction = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: Deno.env.get('OPENAI_MODEL') ?? 'gpt-5-mini',
        input: [
          {
            role: 'system',
            content: 'Extract Arena search intent. Never invent values. Dates use YYYY-MM-DD, time uses HH:mm 24-hour internally. Return null for missing fields.',
          },
          { role: 'user', content: message },
        ],
        text: {
          format: {
            type: 'json_schema',
            name: 'arena_search',
            strict: true,
            schema: {
              type: 'object',
              additionalProperties: false,
              properties: {
                intent: { type: 'string', enum: ['search', 'points', 'coupons', 'next_booking', 'policy', 'other'] },
                sport: { type: ['string', 'null'], enum: ['football', 'padel', 'basketball', 'tennis', null] },
                area: { type: ['string', 'null'] },
                date: { type: ['string', 'null'] },
                time: { type: ['string', 'null'] },
                duration_hours: { type: ['integer', 'null'], minimum: 1, maximum: 8 },
                max_price: { type: ['number', 'null'], minimum: 0 },
                minimum_rating: { type: ['number', 'null'], minimum: 0, maximum: 5 },
              },
              required: ['intent', 'sport', 'area', 'date', 'time', 'duration_hours', 'max_price', 'minimum_rating'],
            },
          },
        },
      }),
    });
    if (!extraction.ok) return json({ error: 'AI_REQUEST_FAILED' }, 502);
    const response = await extraction.json();
    const outputText = response.output_text ?? response.output?.flatMap((item: any) => item.content ?? []).find((item: any) => item.type === 'output_text')?.text;
    const intent = JSON.parse(outputText ?? '{}');

    const { data: profile } = await supabase.from('profiles').select('gender').eq('id', user.id).maybeSingle();
    const gender = profile?.gender;
    if (intent.intent === 'search') {
      if (gender !== 'men' && gender !== 'women') return json({ error: 'PROFILE_GENDER_REQUIRED' }, 400);
      let query = supabase.from('arenas').select('id,name_ar,name_en,area_ar,area_en,location_ar,location_en,price_per_hour,rating,sports,audience_gender').eq('audience_gender', gender).eq('is_active', true);
      if (intent.max_price != null) query = query.lte('price_per_hour', intent.max_price);
      if (intent.minimum_rating != null) query = query.gte('rating', intent.minimum_rating);
      if (intent.area) query = query.or(`area_ar.ilike.%${safe(intent.area)}%,area_en.ilike.%${safe(intent.area)}%,location_ar.ilike.%${safe(intent.area)}%,location_en.ilike.%${safe(intent.area)}%`);
      const { data, error } = await query.limit(20);
      if (error) throw error;
      let arenas = data ?? [];
      if (intent.sport) arenas = arenas.filter((arena: any) => (arena.sports ?? []).some((sport: string) => normalizeSport(sport) === intent.sport));
      const matchingArenas = [...arenas];
      let alternativeStart: Date | null = null;
      if (intent.date && intent.time) {
        const start = new Date(`${intent.date}T${intent.time}:00+04:00`);
        if (Number.isNaN(start.getTime()) || start.getTime() <= Date.now()) {
          return json({
            error: 'INVALID_SEARCH_TIME',
            reply: locale === 'ar'
              ? 'اختر تاريخًا ووقتًا قادمين بصيغة صحيحة.'
              : 'Choose a valid future date and time.',
          }, 400);
        }
        const end = new Date(start.getTime() + (intent.duration_hours ?? 1) * 3600000);
        const available = [];
        for (const arena of arenas.slice(0, 12)) {
          const { data: hasCourt } = await supabase.rpc('arena_has_available_court', {
            p_arena_id: arena.id,
            p_starts_at: start.toISOString(),
            p_ends_at: end.toISOString(),
          });
          if (hasCourt === true) available.push(arena);
        }
        arenas = available;
        if (arenas.length === 0) {
          for (let offset = 1; offset <= 12 && alternativeStart === null; offset += 1) {
            const candidateStart = new Date(start.getTime() + offset * 3600000);
            const candidateEnd = new Date(
              candidateStart.getTime() + (intent.duration_hours ?? 1) * 3600000,
            );
            for (const arena of matchingArenas.slice(0, 8)) {
              const { data: hasCourt } = await supabase.rpc(
                'arena_has_available_court',
                {
                  p_arena_id: arena.id,
                  p_starts_at: candidateStart.toISOString(),
                  p_ends_at: candidateEnd.toISOString(),
                },
              );
              if (hasCourt === true) {
                arenas.push(arena);
                alternativeStart = candidateStart;
                break;
              }
            }
          }
        }
      }
      return json({
        reply: alternativeStart
          ? locale === 'ar'
            ? `لا يوجد ملعب في الوقت المطلوب. أقرب وقت متاح هو ${formatBookingDate(alternativeStart.toISOString(), locale)}.`
            : `Nothing is available at that time. The nearest available time is ${formatBookingDate(alternativeStart.toISOString(), locale)}.`
          : locale === 'ar'
            ? `وجدت ${arenas.length} من الملاعب المطابقة.`
            : `I found ${arenas.length} matching arenas.`,
        arenas: arenas.slice(0, 8),
        alternative_start: alternativeStart?.toISOString() ?? null,
      });
    }
    if (intent.intent === 'points') {
      const { data: rows, error } = await supabase
        .from('point_transactions')
        .select('points')
        .eq('user_id', user.id);
      if (error) throw error;
      const balance = (rows ?? []).reduce((sum: number, row: { points: number }) => sum + row.points, 0);
      return json({
        reply: locale === 'ar' ? `لديك ${balance} نقطة متاحة.` : `You have ${balance} available points.`,
        arenas: [],
      });
    }
    if (intent.intent === 'next_booking') {
      const { data: booking, error } = await supabase
        .from('bookings')
        .select('starts_at,ends_at,arenas(name_ar,name_en)')
        .eq('user_id', user.id)
        .neq('status', 'cancelled')
        .gte('starts_at', new Date().toISOString())
        .order('starts_at')
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      const arena = booking?.arenas as { name_ar?: string; name_en?: string } | null;
      const bookingTime = booking ? formatBookingDate(booking.starts_at, locale) : '';
      return json({
        reply: booking
          ? locale === 'ar'
            ? `حجزك القادم في ${arena?.name_ar ?? 'الملعب'} بتاريخ ${bookingTime}.`
            : `Your next booking is at ${arena?.name_en ?? 'the arena'} on ${bookingTime}.`
          : locale === 'ar' ? 'لا يوجد لديك حجز قادم.' : 'You have no upcoming booking.',
        arenas: [],
      });
    }
    if (intent.intent === 'coupons') {
      const { data: coupons, error } = await supabase
        .from('reward_coupons')
        .select('id,value_omr,status,created_at')
        .eq('user_id', user.id)
        .eq('status', 'available')
        .order('created_at', { ascending: true });
      if (error) throw error;
      const count = coupons?.length ?? 0;
      return json({
        reply: locale === 'ar'
          ? count === 0
            ? 'لا يوجد لديك كوبون متاح حاليًا. تحصل على كوبون بقيمة ريال عماني واحد مقابل كل 100 نقطة، ويمكن اختياره في ملخص الحجز قبل التأكيد.'
            : `لديك ${count} كوبون متاح. اختر الكوبون في ملخص الحجز قبل التأكيد، ويُستخدم مرة واحدة فقط.`
          : count === 0
            ? 'You have no available coupons. Every 100 points creates an OMR 1 coupon that can be selected before confirming a booking.'
            : `You have ${count} available coupon(s). Select one in the booking summary before confirmation; each coupon can be used once.`,
        coupons: coupons ?? [],
        arenas: [],
      });
    }
    if (intent.intent === 'policy') {
      return json({
        reply: locale === 'ar'
          ? 'الحجز يصبح مؤكدًا بعد نجاح العملية. لا يمكن للاعب إلغاء الحجز من طرفه؛ الإلغاء يتم من الإدارة أو صاحب الملعب مع تسجيل السبب والوقت. الحجز الملغي يعيد الوحدة إلى التوفر، وتظهر أي سياسة إضافية يحددها الملعب في صفحة تفاصيله.'
          : 'A booking is confirmed after the transaction succeeds. Players cannot cancel it directly; an administrator or the stadium owner records the cancellation reason and time. A cancelled booking returns its court to availability. Any venue-specific terms appear on the arena details page.',
        arenas: [],
      });
    }
    return json({
      reply: locale === 'ar'
        ? 'أستطيع البحث عن الملاعب المتاحة حسب الرياضة والموقع والتاريخ والوقت والسعر.'
        : 'I can search live arena availability by sport, location, date, time, and price.',
      arenas: [],
    });
  } catch (error) {
    console.error(
      'arena_assistant_failed',
      error instanceof Error ? error.name : 'unknown_error',
    );
    return json({ error: 'ASSISTANT_FAILED' }, 500);
  }
});

function safe(value: string) {
  return value.replace(/[^\p{L}\p{N}\s-]/gu, ' ').trim();
}

function normalizeSport(value: string) {
  const sport = value.trim().toLowerCase();
  if (['football', 'soccer', 'كرة القدم'].includes(sport)) return 'football';
  if (['padel', 'بادل'].includes(sport)) return 'padel';
  if (['basketball', 'كرة السلة'].includes(sport)) return 'basketball';
  if (['tennis', 'تنس'].includes(sport)) return 'tennis';
  return sport;
}

function formatBookingDate(value: string, locale: 'ar' | 'en') {
  return new Intl.DateTimeFormat(locale === 'ar' ? 'ar-OM' : 'en-OM', {
    timeZone: 'Asia/Muscat',
    dateStyle: 'medium',
    timeStyle: 'short',
    hour12: true,
  }).format(new Date(value));
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
