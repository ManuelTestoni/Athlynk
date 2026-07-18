(function () {
  var KEY = 'athlynk_cookie_consent';
  var consent = localStorage.getItem(KEY);

  function loadAnalytics() {
    var s = document.createElement('script');
    s.defer = true;
    s.src = '/_vercel/speed-insights/script.js';
    document.head.appendChild(s);
  }

  function hideBanner() {
    var b = document.getElementById('cookie-banner');
    if (b) b.style.display = 'none';
  }

  // If already decided, act immediately and exit.
  if (consent === 'accepted') { loadAnalytics(); hideBanner(); return; }
  if (consent === 'rejected') { hideBanner(); return; }

  // No stored decision — wire up the banner.
  var acceptBtn = document.getElementById('cookie-accept');
  var rejectBtn = document.getElementById('cookie-reject');
  var declineBtn = document.getElementById('cookie-decline');
  if (!acceptBtn || !rejectBtn) return;

  acceptBtn.addEventListener('click', function () {
    localStorage.setItem(KEY, 'accepted');
    hideBanner();
    loadAnalytics();
  });

  // "Solo necessari" and "Rifiuta" both skip the only non-essential
  // category (analytics) — same outcome, shown as distinct choices per UX.
  function decline() {
    localStorage.setItem(KEY, 'rejected');
    hideBanner();
  }
  rejectBtn.addEventListener('click', decline);
  declineBtn && declineBtn.addEventListener('click', decline);
})();
