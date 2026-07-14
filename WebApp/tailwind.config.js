/** Tailwind build config — sostituisce il CDN (cdn.tailwindcss.com) usato in dev.
 *
 * Rigenerare il CSS dopo aver toccato classi Tailwind in template o JS:
 *   npx tailwindcss@3.4.17 -c tailwind.config.js -i tailwind.input.css \
 *       -o static/css/tailwind.css --minify
 *
 * La palette/typography rispecchia l'ex blocco `tailwind.config` inline di
 * templates/base.html (design system Athlynk).
 */
module.exports = {
  content: [
    './templates/**/*.html',
    './static/js/**/*.js',
  ],
  theme: {
    extend: {
      colors: {
        /* Athlynk palette — deep luxury blue */
        ink:        '#0B1D3A',
        'ink-soft': '#16294A',
        'ink-mute': '#4B5D75',
        'ink-line': '#7C8CA3',

        parchment:    '#FFFFFF',
        marble:       '#F4F6F9',
        'marble-warm':'#EEF1F6',
        stone:        '#E8ECF2',
        'stone-deep': '#C9D2DE',

        /* Brand colors read the same --al-primary-rgb/--al-accent-rgb
           triplets as athlynk.css (per-user override seam), via Tailwind's
           <alpha-value> so bg-aegean/20 etc. keep working. */
        aegean:       'rgb(var(--al-primary-rgb) / <alpha-value>)',
        'aegean-deep':'rgb(var(--al-primary-d-rgb) / <alpha-value>)',
        'aegean-tint':'rgb(var(--al-accent-rgb) / <alpha-value>)',

        /* Bronze retired as a role; kept pointing at primary so any class
           reference not yet migrated degrades to the new primary blue
           instead of the old warm hue. New code should use accent/gold. */
        bronze:        'rgb(var(--al-primary-rgb) / <alpha-value>)',
        'bronze-soft': 'rgb(var(--al-primary-d-rgb) / <alpha-value>)',
        'bronze-light':'rgb(var(--al-accent-rgb) / <alpha-value>)',

        /* New deep-luxury-blue vocabulary */
        'accent-text':       '#3E6E95',
        gold:                '#FFE066',
        'highlight-premium': '#FFE066',

        /* Legacy aliases (do not break old templates) — kept equal to their
           same-named --al-* CSS custom property so nothing silently diverges */
        primary: 'rgb(var(--al-primary-rgb) / <alpha-value>)',
        accent:  'rgb(var(--al-accent-rgb) / <alpha-value>)',
        surface: '#FFFFFF',
        brand:   'rgb(var(--al-primary-rgb) / <alpha-value>)',
      },
      fontFamily: {
        display: ['"Bodoni Moda"', 'Didot', 'Georgia', 'serif'],
        sans:    ['Inter', 'system-ui', 'sans-serif'],
        mono:    ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      boxShadow: {
        'al-1': '0 1px 0 rgba(20,17,13,0.04)',
        'al-2': '0 12px 32px -16px rgba(20,17,13,0.18)',
        'al-3': '0 30px 80px -30px rgba(20,17,13,0.35)',
      },
      borderRadius: {
        'al-sm': '10px',
        'al-md': '16px',
        'al-lg': '22px',
        'al-xl': '28px',
        'al-pill': '999px',
      },
    },
  },
};
