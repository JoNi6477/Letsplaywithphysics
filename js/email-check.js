// Catches mistyped and throwaway email addresses before Supabase sends an email to them.
// Emails to addresses that don't exist "bounce", and too many bounces get the
// project's email sending blocked — so we stop them at the form.

const EMAIL_DOMAINS = [
  'gmail.com', 'googlemail.com', 'yahoo.com', 'yahoo.in', 'yahoo.co.in', 'ymail.com',
  'outlook.com', 'outlook.in', 'hotmail.com', 'live.com', 'live.in', 'msn.com',
  'icloud.com', 'me.com', 'rediffmail.com', 'aol.com', 'proton.me', 'protonmail.com',
  'zoho.com', 'zohomail.in', 'mail.com', 'gmx.com'
];

const BLOCKED_DOMAINS = [
  'example.com', 'example.org', 'example.net', 'test.com', 'test.in', 'email.com', 'domain.com',
  'mailinator.com', 'yopmail.com', 'guerrillamail.com', 'sharklasers.com', '10minutemail.com',
  'temp-mail.org', 'tempmail.com', 'tempmail.net', 'throwawaymail.com', 'trashmail.com',
  'getnada.com', 'maildrop.cc', 'dispostable.com', 'fakeinbox.com', 'mohmal.com', 'emailondeck.com'
];

function editDistance(a, b) {
  const row = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    let prev = row[0];
    row[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const keep = row[j];
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] === b[j - 1] ? 0 : 1));
      prev = keep;
    }
  }
  return row[b.length];
}

// Returns { error } for addresses that can't work, { warning, suggestion } for likely
// typos the student should double-check, or {} when the address looks fine.
function checkEmail(raw) {
  const email = String(raw || '').trim().toLowerCase();
  const at = email.lastIndexOf('@');
  if (at < 1) return { error: 'Please enter a full email address, like name@gmail.com.' };
  const user = email.slice(0, at), domain = email.slice(at + 1);

  if (!/^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/.test(domain) || /\.\.|^\.|\.$/.test(user)) {
    return { error: 'This email address doesn\'t look right. Please check it.' };
  }
  if (BLOCKED_DOMAINS.includes(domain) || /(^|\.)(temp|trash|fake|throwaway)[a-z-]*mail/.test(domain)) {
    return { error: 'Please use your own email address (temporary or sample addresses can\'t receive our emails).' };
  }

  if (!EMAIL_DOMAINS.includes(domain)) {
    const close = EMAIL_DOMAINS
      .map(d => ({ d, n: editDistance(domain, d) }))
      .filter(x => x.n <= 2 && x.n < domain.length / 3)
      .sort((x, y) => x.n - y.n)[0];
    if (close) {
      const suggestion = user + '@' + close.d;
      return { warning: `Did you mean ${suggestion}?`, suggestion };
    }
  }

  if (domain === 'gmail.com') {
    const name = user.split('+')[0];
    if (!/^[a-z0-9.]+$/.test(name)) return { error: 'Gmail addresses can only have letters, numbers and dots before the @.' };
    if (name.replace(/\./g, '').length < 6) {
      return { warning: `Gmail addresses usually have at least 6 characters before the @. Is ${email} correct?` };
    }
  }
  return {};
}
