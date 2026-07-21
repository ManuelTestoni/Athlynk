// Deploy-time asset minifier for the static site.
//
// Minifies every css/*.css and js/*.js IN PLACE using esbuild, then whitenoise-
// style: the repo keeps readable sources, production serves the minified bytes.
// Runs on Vercel (VERCEL env is set there) inside the ephemeral build checkout,
// so the git-tracked sources are never touched. vercel.json removes node_modules
// and this tooling after the build, so the served output ("." ) stays clean.
//
// Guard: a local `npm run build` is a NO-OP unless you pass --force, so you can
// never accidentally overwrite your working-tree sources. Test with:
//   node build.mjs --force   (then `git checkout -- css js` to restore)

import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import esbuild from 'esbuild';

const root = dirname(fileURLToPath(import.meta.url));
const force = process.argv.includes('--force') || !!process.env.VERCEL;

if (!force) {
  console.log('[build] skipped — minify runs only on Vercel (VERCEL env) or with --force.');
  console.log('[build] sources left untouched.');
  process.exit(0);
}

const targets = [
  { dir: 'css', loader: 'css', ext: '.css' },
  { dir: 'js', loader: 'js', ext: '.js' },
];

const kb = (n) => (n / 1024).toFixed(1) + 'KB';
let totBefore = 0;
let totAfter = 0;

for (const { dir, loader, ext } of targets) {
  const abs = join(root, dir);
  let names;
  try {
    names = readdirSync(abs);
  } catch {
    continue; // directory absent — skip
  }
  for (const name of names) {
    if (extname(name).toLowerCase() !== ext) continue;
    if (name.endsWith('.min' + ext)) continue; // already minified
    const file = join(abs, name);
    if (!statSync(file).isFile()) continue;

    const src = readFileSync(file, 'utf8');
    const { code } = esbuild.transformSync(src, {
      loader,
      minify: true,
      legalComments: 'none',
    });
    writeFileSync(file, code, 'utf8');

    const before = Buffer.byteLength(src);
    const after = Buffer.byteLength(code);
    totBefore += before;
    totAfter += after;
    const saved = before ? (100 * (1 - after / before)).toFixed(0) : '0';
    console.log(`[build] ${dir}/${name}  ${kb(before)} -> ${kb(after)}  (-${saved}%)`);
  }
}

const savedTot = totBefore ? (100 * (1 - totAfter / totBefore)).toFixed(0) : '0';
console.log(`[build] total  ${kb(totBefore)} -> ${kb(totAfter)}  (-${savedTot}%)`);
