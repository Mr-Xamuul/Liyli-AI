-- Leyli AI: initial Supabase schema for student profiles and shared library.
-- Apply through the Supabase SQL editor or convert to a CLI migration before deploy.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text not null default 'Arday',
  selected_form text not null default 'Form 1',
  role text not null default 'student' check (role in ('student', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.books (
  id text primary key default gen_random_uuid()::text,
  title text not null,
  subject text not null default '',
  form text not null default 'Form 1',
  description text not null default '',
  cover_path text,
  pdf_path text not null,
  metadata jsonb not null default '{}'::jsonb,
  page_count integer not null default 0 check (page_count >= 0),
  is_published boolean not null default false,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists books_published_form_idx
  on public.books (form, subject, title) where is_published;
create index if not exists books_created_by_idx on public.books (created_by);

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

revoke all on function public.current_user_is_admin() from public;
revoke all on function public.current_user_is_admin() from anon;
grant execute on function public.current_user_is_admin() to authenticated;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', 'Arday')
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

alter table public.profiles enable row level security;
alter table public.books enable row level security;

drop policy if exists "profiles_read_own_or_admin" on public.profiles;
create policy "profiles_read_own_or_admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.current_user_is_admin()));

drop policy if exists "profiles_insert_student_self" on public.profiles;
create policy "profiles_insert_student_self" on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()) and role = 'student');

drop policy if exists "profiles_update_own_student_fields" on public.profiles;
drop policy if exists "profiles_admin_update" on public.profiles;
drop policy if exists "profiles_update_self_or_admin" on public.profiles;
create policy "profiles_update_self_or_admin" on public.profiles
  for update to authenticated
  using (
    (id = (select auth.uid()) and role = 'student')
    or (select public.current_user_is_admin())
  )
  with check (
    (id = (select auth.uid()) and role = 'student')
    or (select public.current_user_is_admin())
  );

drop policy if exists "books_read_published" on public.books;
create policy "books_read_published" on public.books
  for select to authenticated
  using (is_published or (select public.current_user_is_admin()));

drop policy if exists "books_admin_insert" on public.books;
create policy "books_admin_insert" on public.books
  for insert to authenticated
  with check ((select public.current_user_is_admin()));

drop policy if exists "books_admin_update" on public.books;
create policy "books_admin_update" on public.books
  for update to authenticated
  using ((select public.current_user_is_admin()))
  with check ((select public.current_user_is_admin()));

drop policy if exists "books_admin_delete" on public.books;
create policy "books_admin_delete" on public.books
  for delete to authenticated
  using ((select public.current_user_is_admin()));

-- Keep book PDFs private. Store objects as {book-uuid}/original.pdf.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('book-pdfs', 'book-pdfs', false, 52428800, array['application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "book_files_read_published_or_admin" on storage.objects;
create policy "book_files_read_published_or_admin" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'book-pdfs'
    and (
      (select public.current_user_is_admin())
      or exists (
        select 1 from public.books b
        where b.id::text = (storage.foldername(name))[1]
          and b.pdf_path = name
          and b.is_published
      )
    )
  );

drop policy if exists "book_files_admin_insert" on storage.objects;
create policy "book_files_admin_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'book-pdfs' and (select public.current_user_is_admin()));

drop policy if exists "book_files_admin_update" on storage.objects;
create policy "book_files_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'book-pdfs' and (select public.current_user_is_admin()))
  with check (bucket_id = 'book-pdfs' and (select public.current_user_is_admin()));

drop policy if exists "book_files_admin_delete" on storage.objects;
create policy "book_files_admin_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'book-pdfs' and (select public.current_user_is_admin()));

-- Enable live library refreshes when books are published, edited, or removed.
do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'books'
  ) then
    execute 'alter publication supabase_realtime add table public.books';
  end if;
end;
$$;
