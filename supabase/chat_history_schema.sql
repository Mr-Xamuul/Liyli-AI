-- Private per-user AI chat history.
create table if not exists public.chat_sessions (
  user_id uuid not null references auth.users (id) on delete cascade,
  session_id text not null,
  title text not null default 'Sheeko Cusub',
  book_id text,
  updated_at timestamptz not null default now(),
  session_data jsonb not null check (jsonb_typeof(session_data) = 'object'),
  created_at timestamptz not null default now(),
  primary key (user_id, session_id)
);

create index if not exists chat_sessions_user_updated_idx
  on public.chat_sessions (user_id, updated_at desc);

alter table public.chat_sessions enable row level security;
grant select, insert, update, delete on public.chat_sessions to authenticated;
revoke all on public.chat_sessions from anon;

drop policy if exists "chat_sessions_read_own_or_admin" on public.chat_sessions;
create policy "chat_sessions_read_own_or_admin" on public.chat_sessions
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

drop policy if exists "chat_sessions_insert_own" on public.chat_sessions;
create policy "chat_sessions_insert_own" on public.chat_sessions
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "chat_sessions_update_own" on public.chat_sessions;
create policy "chat_sessions_update_own" on public.chat_sessions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "chat_sessions_delete_own_or_admin" on public.chat_sessions;
create policy "chat_sessions_delete_own_or_admin" on public.chat_sessions
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));
