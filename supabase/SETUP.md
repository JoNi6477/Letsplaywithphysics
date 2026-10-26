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
free email-sending service in Supabase. Supabase also warns you (and can stop
sending) if too many emails "bounce" — that is, go to addresses that don't exist.

**Brevo (free, 300 emails a day):**

1. Sign up at **brevo.com** with letsplaywithphysics647742@gmail.com.
2. **Senders, Domains & Dedicated IPs** → **Domains** → **Add a domain** →
   `letsplaywithphysics.in`. Brevo shows a few DNS records (TXT / CNAME).
3. Add those records where you bought the domain (GoDaddy, Hostinger, …) under
   **DNS settings**. Don't touch the existing GitHub Pages records. Back in Brevo,
   click **Verify** (it can take up to a few hours).
4. **Senders** → **Add a sender**: name `Let's Play With Physics`,
   email `noreply@letsplaywithphysics.in`.
5. **SMTP & API** → **SMTP** → **Generate a new SMTP key**. Copy it and the
   **Login** shown on that page.
6. In Supabase: **Authentication** → **Emails** → **SMTP Settings** → turn on
   **Enable custom SMTP** and fill in:
   - Sender email: `noreply@letsplaywithphysics.in`
   - Sender name: `Let's Play With Physics`
   - Host: `smtp-relay.brevo.com` · Port: `587`
   - Username: the Brevo **Login** from step 5
   - Password: the Brevo **SMTP key** from step 5
7. Click **Save**, then create a test account with your own email to check it arrives.

The SMTP key is a password — paste it only into Supabase, never into a website
file or a chat.

The sign-up form already helps keep bounces low: it asks for the email twice,
suggests fixes for typos like `gmial.com`, and refuses throwaway addresses
(`js/email-check.js`).

## Keys — what is safe

- `js/supabase-config.js` contains the **publishable** key. It is meant to be
  public; the security rules in `schema.sql` decide what each person can see.
- **Never** put the **secret** / **service_role** key or the database password in
  any website file or share it with anyone.
