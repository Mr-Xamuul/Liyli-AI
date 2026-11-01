-- Per-user Agent and application monitoring. Both payloads contain student
-- prompts and answers, so RLS limits rows to their owner or an administrator.
create table if not exists public.agent_execution_traces (
  user_id uuid not null references auth.users (id) on delete cascade,
  trace_id text not null,
  created_at timestamptz not null default now(),
  record_data jsonb not null check (jsonb_typeof(record_data) = 'object'),
  primary key (user_id, trace_id)
);

create index if not exists agent_execution_traces_user_created_idx
  on public.agent_execution_traces (user_id, created_at desc);

alter table public.agent_execution_traces enable row level security;
grant select, insert, update, delete on public.agent_execution_traces to authenticated;
revoke all on public.agent_execution_traces from anon;

drop policy if exists "agent_traces_read_own_or_admin" on public.agent_execution_traces;
create policy "agent_traces_read_own_or_admin" on public.agent_execution_traces
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

drop policy if exists "agent_traces_insert_own" on public.agent_execution_traces;
create policy "agent_traces_insert_own" on public.agent_execution_traces
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "agent_traces_update_own" on public.agent_execution_traces;
create policy "agent_traces_update_own" on public.agent_execution_traces
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "agent_traces_delete_own_or_admin" on public.agent_execution_traces;
create policy "agent_traces_delete_own_or_admin" on public.agent_execution_traces
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

create table if not exists public.app_telemetry_logs (
  user_id uuid not null references auth.users (id) on delete cascade,
  log_id text not null,
  created_at timestamptz not null default now(),
  log_data jsonb not null check (jsonb_typeof(log_data) = 'object'),
  primary key (user_id, log_id)
);

create index if not exists app_telemetry_logs_user_created_idx
  on public.app_telemetry_logs (user_id, created_at desc);

alter table public.app_telemetry_logs enable row level security;
grant select, insert, update, delete on public.app_telemetry_logs to authenticated;
revoke all on public.app_telemetry_logs from anon;

drop policy if exists "telemetry_read_own_or_admin" on public.app_telemetry_logs;
create policy "telemetry_read_own_or_admin" on public.app_telemetry_logs
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

drop policy if exists "telemetry_insert_own" on public.app_telemetry_logs;
create policy "telemetry_insert_own" on public.app_telemetry_logs
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "telemetry_update_own" on public.app_telemetry_logs;
create policy "telemetry_update_own" on public.app_telemetry_logs
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "telemetry_delete_own_or_admin" on public.app_telemetry_logs;
create policy "telemetry_delete_own_or_admin" on public.app_telemetry_logs
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

-- Only active executions are stored here; finishing/removing one deletes its row.
create table if not exists public.agent_live_executions (
  user_id uuid not null references auth.users (id) on delete cascade,
  execution_id text not null,
  updated_at timestamptz not null default now(),
  execution_data jsonb not null check (jsonb_typeof(execution_data) = 'object'),
  primary key (user_id, execution_id)
);

create index if not exists agent_live_executions_updated_idx
  on public.agent_live_executions (updated_at desc);

alter table public.agent_live_executions enable row level security;
grant select, insert, update, delete on public.agent_live_executions to authenticated;
revoke all on public.agent_live_executions from anon;

drop policy if exists "agent_live_read_own_or_admin" on public.agent_live_executions;
create policy "agent_live_read_own_or_admin" on public.agent_live_executions
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

drop policy if exists "agent_live_insert_own" on public.agent_live_executions;
create policy "agent_live_insert_own" on public.agent_live_executions
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "agent_live_update_own" on public.agent_live_executions;
create policy "agent_live_update_own" on public.agent_live_executions
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "agent_live_delete_own_or_admin" on public.agent_live_executions;
create policy "agent_live_delete_own_or_admin" on public.agent_live_executions
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.current_user_is_admin()));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'agent_live_executions'
  ) then
    alter publication supabase_realtime add table public.agent_live_executions;
  end if;
end;
$$;
