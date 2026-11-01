# Supabase setup

## App configuration

The local file `supabase.dev.json` is ignored by Git. Start the app with:

```powershell
flutter run --dart-define-from-file=supabase.dev.json
```

Only the project URL and publishable key belong in this file. Never put a
`service_role` or secret key in a Flutter app.

## Database and book storage

Open the [Supabase SQL Editor](https://supabase.com/dashboard/project/fairmxsdgijwexpwkeqx/sql/new)
and run `schema.sql`. This creates student profiles, the shared book catalog,
the private `book-pdfs` bucket, and the row/storage policies.

After a student account has signed in once, promote the trusted administrator
account from the SQL Editor, replacing the address with the administrator's
email:

```sql
update public.profiles
set role = 'admin'
where email = 'admin@example.com';
```

## Email sign-in redirect

In **Authentication → URL Configuration → Redirect URLs**, allow:

```text
io.supabase.flutter://login-callback/
```

For Flutter web, also allow the local development origin (usually
`http://localhost:...`) and the deployed app's HTTPS origin. Email sign-in is
enabled on the connected project; Google sign-in is currently disabled there.
