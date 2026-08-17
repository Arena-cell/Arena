-- Public games, real chat image uploads, and arena classifications.
-- Run once in Supabase SQL Editor.

alter table public.matches
  add column if not exists is_private boolean not null default false;

alter table public.arenas
  add column if not exists audience_gender text not null default 'men'
    check (audience_gender in ('men', 'women'));

comment on column public.arenas.sports is
  'Admin-managed sport types, for example {football} or {padel}.';
comment on column public.arenas.audience_gender is
  'Admin-managed audience: men or women only.';

drop policy if exists "arenas are readable" on public.arenas;
drop policy if exists "public arenas are readable" on public.arenas;
create policy "public arenas are readable"
on public.arenas for select to anon, authenticated using (true);

drop policy if exists "matches are readable" on public.matches;
drop policy if exists "public matches are readable" on public.matches;
drop policy if exists "member matches are readable" on public.matches;
create policy "public matches are readable"
on public.matches for select to anon using (not is_private);
create policy "member matches are readable"
on public.matches for select to authenticated using (
  not is_private
  or host_id = auth.uid()
  or exists (
    select 1 from public.match_players mp
    where mp.match_id = matches.id and mp.user_id = auth.uid()
  )
);

drop policy if exists "match players are readable" on public.match_players;
drop policy if exists "public match players are readable" on public.match_players;
create policy "public match players are readable"
on public.match_players for select to anon, authenticated using (true);

insert into storage.buckets (id, name, public)
values ('chat-images', 'chat-images', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "chat images publicly readable" on storage.objects;
drop policy if exists "users upload own chat images" on storage.objects;
create policy "chat images publicly readable"
on storage.objects for select
using (bucket_id = 'chat-images');
create policy "users upload own chat images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
