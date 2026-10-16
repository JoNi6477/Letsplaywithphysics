// Shows "My Account" instead of "Login" in the menu when a student is signed in.
// Reads only whether a saved session exists, so pages don't need to load Supabase.
(function () {
  var signedIn = false;
  try { signedIn = !!localStorage.getItem('sb-cclwdlijpxsefczgqoou-auth-token'); } catch (e) {}
  document.querySelectorAll('[data-account-link]').forEach(function (a) {
    a.textContent = signedIn ? 'My Account' : 'Login';
    a.href = signedIn ? 'dashboard.html' : 'login.html';
  });
})();
