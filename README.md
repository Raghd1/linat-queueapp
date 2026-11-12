# Virtual Queue

Customers scan a QR code, enter their name and party size, and watch their place in line live.
Their phone beeps when they're called. Staff run the line from one dashboard.

- `public/join.html`: customer page (the QR code points here)
- `public/staff.html`: staff dashboard (call next, done / no-show, add walk-ins, QR code)
- `supabase/schema.sql`: database, security rules, queue logic, live updates
- `supabase/test.sql`: self-check for the queue logic

## Setup (about 10 minutes)

1. **Create a Supabase project** at supabase.com (the free tier is fine).
2. **SQL Editor:** paste and run `supabase/schema.sql`. First change `'UTC'` in `queue_tz()`
   to your timezone (e.g. `'America/New_York'`) so the line resets at your midnight.
3. **SQL Editor:** run `supabase/test.sql`. You should see `ALL TESTS PASSED`. It rolls back, so no data changes.
4. **Create the staff login:** Authentication → Users → *Add user*. Enter any email (e.g. `staff@yourshop.com`)
   and the shared staff password, with *Auto confirm* ticked. Then in the SQL Editor:
   ```sql
   update auth.users set raw_app_meta_data = raw_app_meta_data || '{"role":"staff"}'
   where email = 'staff@yourshop.com';
   ```
   Only this user can see the queue. Also turn off *Allow new users to sign up*
   (Authentication → Sign In / Providers).
5. **Fill in `public/config.js`:** Project URL and anon key (Project Settings → API), plus the staff email.
6. **Deploy `public/`** to any static host (Netlify drop, Vercel, GitHub Pages, Cloudflare Pages).
7. Open `staff.html`, log in, open *QR code for customers* and print it.

Try it locally: `npx serve public`, then open `/join.html` and `/staff.html` in two windows.

## How it works

- Customers never read the database directly. They call `join_queue` and `get_status`, which only
  return *their* position, so other people's names stay private.
- Estimated wait = your position × the average time between the last 10 "Call next" clicks today
  (5 minutes until there's data).
- Whenever the queue changes, a database trigger sends an empty "changed" message on a Realtime
  channel. Open pages re-fetch. Pages also re-check every 30 s and whenever they come back to the foreground.
- Your ticket link (`join.html?id=…`) survives a reload. Bookmark it or keep the tab open.

## Limits to know

- Alerts only work while the page is open. If the phone is locked or the browser is closed, nothing
  beeps until the customer looks again. iPhones don't vibrate from web pages.
- Anyone with the link can join with any name (no rate limit). Staff can remove fake entries.
