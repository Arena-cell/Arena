-- Run this once in Supabase Dashboard > SQL Editor. It creates private 1:1 messaging.
create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  content text,
  image_url text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (content is not null or image_url is not null)
);
create table if not exists public.friend_requests (
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  primary key (sender_id, receiver_id), check (sender_id <> receiver_id)
);
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id), check (blocker_id <> blocked_id)
);
alter table public.direct_messages enable row level security;
alter table public.friend_requests enable row level security;
alter table public.user_blocks enable row level security;
create policy "message participants only" on public.direct_messages for all using (auth.uid() in (sender_id, receiver_id)) with check (auth.uid() = sender_id);
create policy "friend request participants" on public.friend_requests for all using (auth.uid() in (sender_id, receiver_id)) with check (auth.uid() = sender_id);
create policy "own block list" on public.user_blocks for all using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);
