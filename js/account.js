// Shared helpers for the student account pages (login, dashboard, admin).
// Needs supabase-config.js and the supabase-js library loaded first.

const CONTENT_TYPES = {
  mocks:       { label: 'Mock Tests',     icon: '📝', link: 'mocktest.html',    desc: 'NEET & JEE Mains physics mock tests in the real NTA exam format.' },
  simulations: { label: 'Simulations',    icon: '🧪', link: 'simulations.html', desc: 'Interactive simulations to see physics in action.' },
  videos:      { label: 'Video Lectures', icon: '🎬', link: null,               desc: 'Full video lectures with notes — launching soon.' }
};

const sb = window.supabase.createClient(LPWP_CONFIG.supabaseUrl, LPWP_CONFIG.supabaseKey, {
  // "implicit" lets email links work even when opened in a different browser or device
  auth: { flowType: 'implicit', persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

const $ = id => document.getElementById(id);

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

function formatInr(amount) {
  return '₹' + Number(amount).toLocaleString('en-IN');
}

// Only allow redirects to pages on this site (blocks "?next=https://evil.com").
function safeNext(fallback) {
  const next = new URLSearchParams(location.search).get('next') || '';
  return /^[a-z0-9-]+\.html(#[a-z0-9-]*)?$/i.test(next) ? next : fallback;
}

function pageUrl(page) {
  return new URL(page, location.href).href;
}

// Returns the signed-in user, or sends them to the login page.
async function requireUser() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) {
    const here = location.pathname.split('/').pop() || 'dashboard.html';
    location.replace('login.html?next=' + encodeURIComponent(here));
    return null;
  }
  return session.user;
}

function enrollmentStatus(e, now = new Date()) {
  if (new Date(e.starts_at) > now) return 'upcoming';
  if (new Date(e.expires_at) <= now) return 'expired';
  return 'active';
}

// For each content type, the latest expiry date among the student's active plans.
function accessByType(enrollments) {
  const access = {};
  for (const e of enrollments) {
    if (enrollmentStatus(e) !== 'active' || !e.plans) continue;
    for (const kind of e.plans.unlocks) {
      if (!access[kind] || new Date(e.expires_at) > new Date(access[kind])) access[kind] = e.expires_at;
    }
  }
  return access;
}

function showMessage(el, text, kind = 'info') {
  el.className = 'msg msg-' + kind;
  el.textContent = text;
  el.hidden = !text;
}

// Turns Supabase's technical errors into plain English.
function friendlyError(error) {
  const m = (error && error.message) || String(error);
  if (/invalid login credentials/i.test(m)) return 'Wrong email or password.';
  if (/email not confirmed/i.test(m)) return 'Please confirm your email first. Check your inbox (and spam folder) for the link we sent.';
  if (/already registered|already been registered/i.test(m)) return 'An account with this email already exists. Try logging in, or use "Forgot password".';
  if (/rate limit|too many/i.test(m)) return 'Too many attempts. Please wait a few minutes and try again.';
  if (/password should be at least/i.test(m)) return 'Password must be at least 8 characters.';
  if (/failed to fetch|network/i.test(m)) return 'Could not connect. Check your internet connection and try again.';
  return m;
}

function toggleMenu() {
  $('mobile-menu').classList.toggle('open');
  $('hamburger').classList.toggle('open');
}
