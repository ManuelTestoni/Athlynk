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
        /* Athlynk palette */
        ink:        '#14110d',
        'ink-soft': '#2a2620',
        'ink-mute': '#5b554a',
        'ink-line': '#8a8270',

        parchment:    '#f4efe4',
        marble:       '#ece5d6',
        'marble-warm':'#e7dfcb',
        stone:        '#d8cfba',
        'stone-deep': '#c4b89c',

        aegean:       '#1c4a52',
        'aegean-deep':'#0e2f36',
        'aegean-tint':'#2a6a72',

        bronze:        '#8a6a3a',
        'bronze-soft': '#a78554',
        'bronze-light':'#c8a774',

        /* Legacy aliases (do not break old templates) */
        primary: '#14110d',
        accent:  '#1c4a52',
        surface: '#f4efe4',
        brand:   '#8a6a3a',
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
