// Fill these in from Supabase → Project Settings → API.
// The anon key is meant to be public; row-level security protects the data.
const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-KEY';
// The single staff login's email. Staff only type the shared password.
const STAFF_EMAIL = 'staff@example.com';

const db = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Re-run `fn` whenever the queue changes, plus every 30 s in case a phone dropped the live connection.
function onQueueChange(fn) {
  db.channel('queue').on('broadcast', { event: 'changed' }, fn).subscribe();
  setInterval(fn, 30000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) fn(); });
}
