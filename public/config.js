// Fill these in from Supabase → Project Settings → API.
// The anon key is meant to be public; row-level security protects the data.
const SUPABASE_URL = 'https://hswqtiyewvgoivmqoswc.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_X2vi2xbG3Xmn4vBM4Nwc6Q_9huOMTRz';
// The single staff login's email. Staff only type the shared password.
const STAFF_EMAIL = 'staff@example.com';

// Staff login lives in sessionStorage, so closing the browser (or tab) logs staff out.
let authStorage;
try {
  authStorage = sessionStorage;
  // Drop logins saved by the old localStorage setting so they can't linger on the device.
  Object.keys(localStorage).filter((k) => /^sb-.*-auth-token$/.test(k)).forEach((k) => localStorage.removeItem(k));
} catch {}
const db = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { storage: authStorage } });

// Re-run `fn` whenever the queue changes, plus every 30 s in case a phone dropped the live connection.
function onQueueChange(fn) {
  db.channel('queue').on('broadcast', { event: 'changed' }, fn).subscribe();
  setInterval(fn, 30000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) fn(); });
}
