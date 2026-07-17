# Response headers

Why `vercel.json` looks the way it does. (`vercel.json` can't hold comments —
its schema rejects unknown keys, so the reasoning lives here.)

## Security baseline — enforced

`Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`,
`Referrer-Policy`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`.

Safe to enforce: none of them can break a static page. `Permissions-Policy`
denies every capability the site doesn't use, and keeps `autoplay` and
`fullscreen` on `self` for the hero film.

## CSP — deliberately Report-Only

`Content-Security-Policy-Report-Only` **warns, it does not block.** It is not
enforced yet, and that is on purpose. Two things must be settled first:

1. **`acquista.html` carries an ~80-line inline checkout script** that drives
   the Stripe redirect. Enforcing CSP requires either moving it into `/js/` or
   pinning it to a `sha256-…` hash. A hash is the trap: edit the script, forget
   the hash, and **payments break silently in production**. Externalising it is
   the better fix, but it must be tested against a real Stripe round-trip first.
2. **~80 inline `style=` attributes** across the pages force
   `style-src 'unsafe-inline'` until they move into `style.css`.

So today's policy still allows `'unsafe-inline'` for both scripts and styles —
which means that, even enforced, it would not stop an injected inline script.
Shipping it Report-Only is honest about that rather than pretending to a
protection the site doesn't have.

### Before flipping the key

1. Deploy, then click through **home → pricing → acquista → Stripe → return**
   with the console open.
2. Fix everything reported. Expect noise from the inline script and style attrs.
3. Externalise the checkout script; drop `'unsafe-inline'` from `script-src`.
4. Only then rename the header to `Content-Security-Policy`.

Vercel Speed Insights (`/_vercel/speed-insights/script.js`, loaded by
`js/cookie-consent.js` only after consent) is same-origin, so `script-src 'self'`
and `connect-src 'self'` already cover it.

## CORS — scoped on purpose

The site is static and same-origin: a blanket `Access-Control-Allow-Origin: *`
would grant nothing, so it isn't set globally. It's opened only where a
cross-origin read is actually plausible:

- **`/assets/*`** — the mark and OG cover, which get hotlinked and embedded.
  `Cross-Origin-Resource-Policy: cross-origin` is required alongside it, or
  `Cross-Origin-Opener-Policy: same-origin` above would block the very reads
  the CORS header is there to allow.
- **`/llms.txt`** — it exists to be fetched by agents that are not a browser on
  this origin. Also pinned to `text/plain` so it renders instead of downloading.

## Caching

HTML revalidates every request (cheap, keeps copy edits instant). CSS and JS
are busted by the `?v=` query in the markup. `/assets/*` is cached for a week —
those files change rarely and are busted by filename.
