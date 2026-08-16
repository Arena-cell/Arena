-- Run once in Supabase SQL Editor.
-- Correct legacy arena prices that are within 20 baisa of a whole rial.
update public.arenas
set price_per_hour = round(price_per_hour)
where abs(price_per_hour - round(price_per_hour)) <= 0.020001;

alter table public.arenas
  alter column price_per_hour type numeric(10,2)
  using round(price_per_hour::numeric, 2);

alter table public.matches
  alter column price_per_player type numeric(10,2)
  using round(price_per_player::numeric, 2);

alter table public.bookings
  alter column total_price type numeric(10,2)
  using round(total_price::numeric, 2);
