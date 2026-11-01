-- AI Manage settings. Provider credentials never live in these tables.

create table if not exists public.ai_admin_settings (
  setting_key text primary key,
  setting_value jsonb not null,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);

create index if not exists ai_admin_settings_updated_by_idx
  on public.ai_admin_settings (updated_by);

alter table public.ai_admin_settings enable row level security;

drop policy if exists "ai_settings_read_authenticated" on public.ai_admin_settings;
create policy "ai_settings_read_authenticated" on public.ai_admin_settings
  for select to authenticated using (true);

drop policy if exists "ai_settings_admin_insert" on public.ai_admin_settings;
create policy "ai_settings_admin_insert" on public.ai_admin_settings
  for insert to authenticated
  with check ((select public.current_user_is_admin()));

drop policy if exists "ai_settings_admin_update" on public.ai_admin_settings;
create policy "ai_settings_admin_update" on public.ai_admin_settings
  for update to authenticated
  using ((select public.current_user_is_admin()))
  with check ((select public.current_user_is_admin()));

drop policy if exists "ai_settings_admin_delete" on public.ai_admin_settings;
create policy "ai_settings_admin_delete" on public.ai_admin_settings
  for delete to authenticated
  using ((select public.current_user_is_admin()));

create table if not exists public.ai_api_keys (
  id text primary key,
  name text not null,
  provider text not null,
  base_url text not null,
  is_active boolean not null default true,
  has_secret boolean not null default false,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ai_api_keys enable row level security;

drop policy if exists "ai_api_keys_admin_read" on public.ai_api_keys;
create policy "ai_api_keys_admin_read" on public.ai_api_keys
  for select to authenticated
  using ((select public.current_user_is_admin()));

-- The following functions are only callable by the Edge Function's
-- service_role client. They do not return plaintext except for the restricted
-- read function used by the AI gateway, which must never be called by a client.
create or replace function public.ai_vault_store_secret(
  p_key_id text,
  p_secret text,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  secret_id uuid;
  secret_name text;
begin
  if p_key_id !~ '^[A-Za-z0-9_-]{1,120}$' or length(p_secret) = 0 then
    raise exception 'Invalid API key input';
  end if;
  secret_name := 'leyli-ai-key:' || p_key_id;
  select id into secret_id from vault.secrets where name = secret_name limit 1;
  if secret_id is null then
    perform vault.create_secret(p_secret, secret_name, p_description);
  else
    perform vault.update_secret(secret_id, p_secret, secret_name, p_description);
  end if;
end;
$$;

create or replace function public.ai_vault_read_secret(p_key_id text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = 'leyli-ai-key:' || p_key_id
  limit 1;
$$;

create or replace function public.ai_vault_delete_secret(p_key_id text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from vault.secrets where name = 'leyli-ai-key:' || p_key_id;
$$;

revoke all on function public.ai_vault_store_secret(text, text, text) from public, anon, authenticated;
revoke all on function public.ai_vault_read_secret(text) from public, anon, authenticated;
revoke all on function public.ai_vault_delete_secret(text) from public, anon, authenticated;
grant execute on function public.ai_vault_store_secret(text, text, text) to service_role;
grant execute on function public.ai_vault_read_secret(text) to service_role;
grant execute on function public.ai_vault_delete_secret(text) to service_role;

-- Atomic per-user budget guard for provider calls. No client role can inspect
-- or mutate counters directly; the gateway calls the service-only RPC.
create table if not exists public.ai_gateway_usage (
  user_id uuid primary key references auth.users (id) on delete cascade,
  minute_window timestamptz not null,
  minute_count integer not null default 0,
  day_window date not null,
  day_count integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.ai_gateway_usage enable row level security;
revoke all on public.ai_gateway_usage from public, anon, authenticated;
grant all on public.ai_gateway_usage to service_role;
drop policy if exists "ai_gateway_usage_deny_clients" on public.ai_gateway_usage;
create policy "ai_gateway_usage_deny_clients" on public.ai_gateway_usage
  for all to anon, authenticated using (false) with check (false);

create or replace function public.ai_gateway_consume_budget(
  p_user_id uuid,
  p_is_admin boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowed boolean;
begin
  insert into public.ai_gateway_usage as usage (
    user_id, minute_window, minute_count, day_window, day_count, updated_at
  ) values (
    p_user_id, date_trunc('minute', now()), 1, current_date, 1, now()
  )
  on conflict (user_id) do update set
    minute_count = case
      when usage.minute_window = date_trunc('minute', now()) then usage.minute_count + 1
      else 1
    end,
    minute_window = date_trunc('minute', now()),
    day_count = case
      when usage.day_window = current_date then usage.day_count + 1
      else 1
    end,
    day_window = current_date,
    updated_at = now()
  returning
    (minute_count <= case when p_is_admin then 60 else 20 end)
    and (day_count <= case when p_is_admin then 3000 else 300 end)
  into allowed;
  return allowed;
end;
$$;

revoke all on function public.ai_gateway_consume_budget(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.ai_gateway_consume_budget(uuid, boolean)
  to service_role;

-- This existing event-trigger helper must be run only by Postgres DDL events,
-- never through the public RPC surface.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke all on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end;
$$;
