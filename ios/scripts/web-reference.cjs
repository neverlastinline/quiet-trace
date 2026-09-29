// Measures every drawing in ../../shapes.js with a real browser's SVG engine and
// writes the result as a fixture for the Swift parity tests, so the iOS app traces
// exactly the same guides as the web app.
//
//   NODE_PATH="$(npm root -g)" node ios/scripts/web-reference.cjs
//
// Needs Playwright with Chromium. Rerun it whenever shapes.js changes.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'ios/QuietTraceKit/Tests/QuietTraceKitTests/Fixtures/web-reference.json');
const STEP = 1.2;  // app.js STEP
const EVERY = 8;   // keep every 8th guide point (plus the last) to keep the file small

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setContent('<!doctype html><body></body>');
  await page.addScriptTag({ content: fs.readFileSync(path.join(ROOT, 'shapes.js'), 'utf8') });
  const items = await page.evaluate(({ step, every }) => {
    const round = (v) => Math.round(v * 1000) / 1000;
    const out = [];
    for (const [category, group] of Object.entries(QT.items)) {
      for (const [name, d] of Object.entries(group)) {
        const strokes = QT.measure(d, step).map((s) => {
          const points = [];
          s.pts.forEach((p, i) => {
            if (i % every === 0 || i === s.pts.length - 1) points.push([i, round(p.x), round(p.y)]);
          });
          return { length: round(s.len), count: s.pts.length, points };
        });
        out.push({ category, name, strokes });
      }
    }
    return out;
  }, { step: STEP, every: EVERY });
  await browser.close();
  fs.writeFileSync(OUT, JSON.stringify({ step: STEP, items }) + '\n');
  console.log(`wrote ${items.length} drawings to ${path.relative(ROOT, OUT)}`);
})().catch((e) => { console.error(e); process.exit(1); });
