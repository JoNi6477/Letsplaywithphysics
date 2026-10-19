# Student accounts — one-time setup

Do these steps once, in order, in the Supabase dashboard for the
`letsplaywithphysics` project.

## 1. Create the database tables

1. Open **SQL Editor** → **New query**.
2. Paste the whole of [`schema.sql`](schema.sql) and click **Run**.
3. You should see "Success. No rows returned". (Running it again later is safe.)

## 1b. Set up the protected mock tests

1. **SQL Editor** → **New query**.
2. Paste the whole of [`mock-tests.sql`](mock-tests.sql) and click **Run**.

This moves the mock test questions into the database. Only students with an
active plan that includes **Mock Tests** (and admins) can open a test, and
answers are only shown after submitting. The JEE test starts switched off
(it has only 2 questions); switch it on in **Table Editor** → `tests` →
`is_active` once more questions are added.

## 2. Login settings

Open **Authentication** → **URL Configuration**:

- **Site URL:** `https://letsplaywithphysics.in`
- **Redirect URLs:** add `https://letsplaywithphysics.in/**`

Open **Authentication** → **Sign In / Providers** → **Email**:

- **Enable Email provider:** on
- **Confirm email:** on
- **Minimum password length:** 8

## 3. Make yourself the admin

1. On the live website, click **Login** → **Create account** and sign up with
   your own email. Confirm it from your inbox.
2. Back in **SQL Editor**, run this (put in your email):

   ```sql
   insert into public.admins (user_id)
   select id from auth.users where email = 'your-email@example.com'
   on conflict do nothing;
   ```

3. Log in on the website. You will now see **Admin** in the menu.

To remove an admin later:

```sql
delete from public.admins
where user_id = (select id from auth.users where email = 'their-email@example.com');
```

## 4. Before launching to many students: your own email sender

Supabase's built-in email service only sends a small number of emails per hour
and is meant for testing. Before you announce accounts to all students, set up a
free email-sending service (for example Brevo or Resend) in
**Authentication** → **Emails** → **SMTP Settings**, so sign-up and
password-reset emails always arrive.

## Keys — what is safe

- `js/supabase-config.js` contains the **publishable** key. It is meant to be
  public; the security rules in `schema.sql` decide what each person can see.
- **Never** put the **secret** / **service_role** key or the database password in
  any website file or share it with anyone.
