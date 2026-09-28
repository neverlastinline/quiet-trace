/* Quiet Trace: pick a colour, then trace one thing after another, for as long as you like. */
(function () {
  'use strict';

  // ---- settings ----

  const COLOURS = [
    ['rose', '#F28B9B'], ['peach', '#F6A96B'], ['sunflower', '#F2C94C'], ['mint', '#6FCF97'],
    ['sky', '#56CCF2'], ['ocean', '#5B8DEF'], ['lavender', '#A98BEA'], ['berry', '#D16BA5'],
  ];
  // How often each kind of thing comes up. Never the same kind twice in a row.
  const WEIGHTS = { objects: 0.35, shapes: 0.25, letters: 0.25, squiggles: 0.15 };

  // Drawing sizes are in box units: every item lives in a 100 × 100 box.
  const BOX = 0.74;          // share of the shorter screen side the box fills
  const INK = 3.4;           // her line width
  const TRACK = 6.5;         // soft track under the guide
  const DASH_W = 1.6;
  const DASH = [2.8, 3.2];
  const REACH = 5.5;         // how near her line must pass for a guide point to count
  const STEP = 1.2;          // spacing of guide points

  const DONE_AT = 0.85;      // share of guide points covered to finish...
  const IDLE_DONE_AT = 0.65; // ...or this much, followed by a pause
  const IDLE_MS = 3000;

  const SWEEP_MS = 900, GLOW_MS = 1400, HOLD_MS = 2700, FADE_MS = 850;
  const EXIT_HOLD_MS = 3000;

  const TRACK_COLOUR = '#EFE8DD', DASH_COLOUR = '#CDC3B4';
  const TAU = Math.PI * 2;

  // ---- elements ----

  const $ = (id) => document.getElementById(id);
  const picker = $('picker'), swatches = $('swatches'), stage = $('stage'), art = $('art'), exitZone = $('exit');
  const guideCv = $('guide'), inkCv = $('ink'), fxCv = $('fx');
  const guideCtx = guideCv.getContext('2d'), inkCtx = inkCv.getContext('2d'), fxCtx = fxCv.getContext('2d');

  // ---- state ----

  let state = 'picking';     // picking | changing | tracing | celebrating
  let colour = COLOURS[0][1], tint = '#fff';
  let W = 0, H = 0, S = 1, OX = 0, OY = 0, DPR = 1;

  let item = null;           // { cat, name, strokes: [{ path, len, pts }], length, samples: [{ x, y, hit }] }
  let covered = 0;
  let sweep = 0;             // 0..1 how far the finished colour has run along the guide
  let lines = [];            // her lines, in box units: [[{ x, y, w }]]
  let current = null;
  let activeId = null, activeType = '';
  let penSeen = false;
  let drawnYet = false;
  let idleTimer = 0;

  const fx = { running: false, dot: 0, sweepStart: 0, glowStart: 0, sparkles: [] };

  let timers = [];
  function later(ms, fn) { timers.push(setTimeout(fn, ms)); }
  function cancelLater() { timers.forEach(clearTimeout); timers = []; }

  // ---- colour picker ----

  COLOURS.forEach(([name, c], i) => {
    const b = document.createElement('button');
    b.className = 'swatch';
    b.setAttribute('aria-label', name);
    b.style.setProperty('--c', c);
    b.style.setProperty('--i', i);
    b.addEventListener('click', () => choose(b, c));
    swatches.appendChild(b);
  });

  function choose(btn, c) {
    if (state !== 'picking') return;
    state = 'changing';
    unlockAudio();
    colour = c;
    tint = mix(c, '#FFFFFF', 0.55);
    btn.classList.add('chosen');
    picker.classList.add('leaving');
    later(650, () => {
      picker.classList.remove('on');
      stage.classList.add('on');
      layout();
    });
    later(1150, () => { nextItem(); art.classList.remove('hide'); });
  }

  function backToPicker() {
    cancelLater();
    clearTimeout(idleTimer);
    state = 'picking';
    activeId = null;
    current = null;
    art.classList.add('hide');
    stage.classList.remove('on');
    picker.classList.remove('leaving');
    swatches.querySelectorAll('.chosen').forEach((b) => b.classList.remove('chosen'));
    picker.classList.add('on');
    later(800, () => { item = null; clear(guideCtx); clear(inkCtx); clear(fxCtx); });
  }

  // ---- choosing what comes next ----

  let lastCat = null;
  const bags = {};

  function pickCategory() {
    const cats = Object.keys(WEIGHTS).filter((c) => c !== lastCat);
    let r = Math.random() * cats.reduce((sum, c) => sum + WEIGHTS[c], 0);
    let cat = cats[cats.length - 1];
    for (const c of cats) {
      r -= WEIGHTS[c];
      if (r <= 0) { cat = c; break; }
    }
    lastCat = cat;
    return cat;
  }

  // Each kind has a shuffled bag, so nothing repeats until the whole bag is used.
  function takeFrom(cat) {
    if (!bags[cat] || !bags[cat].length) {
      const names = Object.keys(QT.items[cat]);
      for (let i = names.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [names[i], names[j]] = [names[j], names[i]];
      }
      bags[cat] = names;
    }
    return bags[cat].pop();
  }

  const built = {};
  function build(cat, name) {
    const key = cat + ':' + name;
    if (!built[key]) {
      const strokes = QT.measure(QT.items[cat][name], STEP).map((s) => ({ path: new Path2D(s.d), len: s.len, pts: s.pts }));
      built[key] = { cat, name, strokes, length: strokes.reduce((sum, s) => sum + s.len, 0) };
    }
    const base = built[key];
    return Object.assign({}, base, {
      samples: base.strokes.flatMap((s) => s.pts.map((p) => ({ x: p.x, y: p.y, hit: false }))),
    });
  }

  function nextItem() {
    const cat = pickCategory();
    item = build(cat, takeFrom(cat));
    lines = [];
    current = null;
    activeId = null;
    covered = 0;
    sweep = 0;
    drawnYet = false;
    fx.dot = 0;
    fx.sweepStart = fx.glowStart = 0;
    fx.sparkles = [];
    redrawInk();
    clear(fxCtx);
    drawGuide();
    state = 'tracing';
    kickFx();
  }

  // ---- layout and drawing ----

  function layout() {
    DPR = Math.min(window.devicePixelRatio || 1, 3);
    W = window.innerWidth;
    H = window.innerHeight;
    S = Math.min(W, H) * BOX;
    OX = (W - S) / 2;
    OY = (H - S) / 2;
    for (const cv of [guideCv, inkCv, fxCv]) {
      cv.width = Math.round(W * DPR);
      cv.height = Math.round(H * DPR);
      cv.style.width = W + 'px';
      cv.style.height = H + 'px';
    }
    if (item) { drawGuide(); redrawInk(); kickFx(); }
  }

  function clear(ctx) {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
  }

  function toBox(ctx) {
    const k = DPR * S / 100;
    ctx.setTransform(k, 0, 0, k, DPR * OX, DPR * OY);
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
  }

  function drawGuide() {
    const ctx = guideCtx;
    clear(ctx);
    if (!item) return;
    toBox(ctx);
    ctx.strokeStyle = TRACK_COLOUR;
    ctx.lineWidth = TRACK;
    for (const s of item.strokes) ctx.stroke(s.path);
    ctx.strokeStyle = DASH_COLOUR;
    ctx.lineWidth = DASH_W;
    ctx.setLineDash(DASH);
    for (const s of item.strokes) ctx.stroke(s.path);
    ctx.setLineDash([]);
    if (sweep > 0) {
      // The finished colour runs along the guide, stroke by stroke.
      ctx.strokeStyle = colour;
      ctx.globalAlpha = 0.45;
      ctx.lineWidth = TRACK;
      let left = sweep * item.length;
      for (const s of item.strokes) {
        const f = Math.min(1, left / s.len);
        left -= s.len;
        if (f <= 0) break;
        if (f < 1) ctx.setLineDash([f * s.len, s.len + 1]);
        ctx.stroke(s.path);
        ctx.setLineDash([]);
      }
      ctx.globalAlpha = 1;
    }
  }

  function prepInk() {
    toBox(inkCtx);
    inkCtx.strokeStyle = colour;
    inkCtx.fillStyle = colour;
  }

  const mid = (a, b) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });

  // Draws the piece of a line that point i adds, smoothed through midpoints.
  function inkPiece(line, i) {
    const ctx = inkCtx, p = line[i];
    ctx.beginPath();
    if (i === 0) {
      ctx.arc(p.x, p.y, p.w / 2, 0, TAU);
      ctx.fill();
      return;
    }
    const a = line[i - 1];
    ctx.lineWidth = p.w;
    if (i === 1) {
      const m = mid(a, p);
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(m.x, m.y);
    } else {
      const m1 = mid(line[i - 2], a), m2 = mid(a, p);
      ctx.moveTo(m1.x, m1.y);
      ctx.quadraticCurveTo(a.x, a.y, m2.x, m2.y);
    }
    ctx.stroke();
  }

  function inkTail(line) {
    if (line.length < 2) return;
    const a = line[line.length - 2], p = line[line.length - 1], m = mid(a, p);
    inkCtx.lineWidth = p.w;
    inkCtx.beginPath();
    inkCtx.moveTo(m.x, m.y);
    inkCtx.lineTo(p.x, p.y);
    inkCtx.stroke();
  }

  function redrawInk() {
    clear(inkCtx);
    prepInk();
    for (const line of lines) {
      for (let i = 0; i < line.length; i++) inkPiece(line, i);
      if (line !== current) inkTail(line);
    }
  }

  // ---- tracing ----

  function addPoint(ev) {
    const x = (ev.clientX - OX) * 100 / S, y = (ev.clientY - OY) * 100 / S;
    const prev = current[current.length - 1];
    if (prev && (x - prev.x) ** 2 + (y - prev.y) ** 2 < 0.04) return;
    let w = INK;
    if (ev.pointerType === 'pen' && ev.pressure > 0) w = INK * (0.7 + 0.7 * Math.min(1, ev.pressure));
    if (prev) w = prev.w * 0.6 + w * 0.4;
    const p = { x, y, w };
    current.push(p);
    inkPiece(current, current.length - 1);
    cover(prev || p, p);
  }

  // Marks guide points within reach of the segment a→b.
  function cover(a, b) {
    const r2 = REACH * REACH, dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy;
    for (const s of item.samples) {
      if (s.hit) continue;
      let t = len2 ? ((s.x - a.x) * dx + (s.y - a.y) * dy) / len2 : 0;
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      const ex = a.x + t * dx - s.x, ey = a.y + t * dy - s.y;
      if (ex * ex + ey * ey <= r2) { s.hit = true; covered++; }
    }
  }

  function recount() {
    covered = 0;
    for (const s of item.samples) s.hit = false;
    for (const line of lines) line.forEach((p, i) => cover(line[i - 1] || p, p));
  }

  function onDown(e) {
    wakeAudio();
    const pen = e.pointerType === 'pen';
    if (pen) penSeen = true;
    if (state !== 'tracing') return;
    // Once a pencil has been used, fingers and palms are ignored.
    if (e.pointerType === 'touch' && penSeen) return;
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    if (activeId !== null) {
      if (!(pen && activeType === 'touch')) return;
      // A palm landed before the pencil: drop the palm's line.
      lines.pop();
      current = null;
      redrawInk();
      recount();
    }
    e.preventDefault();
    activeId = e.pointerId;
    activeType = e.pointerType;
    try { stage.setPointerCapture(e.pointerId); } catch (_) { /* synthetic or already released */ }
    clearTimeout(idleTimer);
    drawnYet = true;
    current = [];
    lines.push(current);
    addPoint(e);
  }

  function onMove(e) {
    if (e.pointerId !== activeId || !current) return;
    e.preventDefault();
    const list = e.getCoalescedEvents ? e.getCoalescedEvents() : [];
    for (const ev of list.length ? list : [e]) addPoint(ev);
  }

  function onUp(e) {
    if (e.pointerId !== activeId) return;
    if (current) inkTail(current);
    current = null;
    activeId = null;
    if (state !== 'tracing') return;
    const done = covered / item.samples.length;
    if (done >= DONE_AT) later(250, celebrate);
    else if (done >= IDLE_DONE_AT) idleTimer = setTimeout(celebrate, IDLE_MS);
  }

  stage.addEventListener('pointerdown', onDown);
  stage.addEventListener('pointermove', onMove);
  stage.addEventListener('pointerup', onUp);
  stage.addEventListener('pointercancel', onUp);

  // Keep iOS from scrolling, zooming or showing the magnifier while she draws.
  stage.addEventListener('touchstart', (e) => e.preventDefault(), { passive: false });
  stage.addEventListener('contextmenu', (e) => e.preventDefault());
  document.addEventListener('gesturestart', (e) => e.preventDefault());
  document.addEventListener('dblclick', (e) => e.preventDefault());

  // Grown-up exit: hold the top-left corner for three seconds.
  let exitTimer = 0;
  exitZone.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    clearTimeout(exitTimer);
    exitTimer = setTimeout(backToPicker, EXIT_HOLD_MS);
  });
  for (const t of ['pointerup', 'pointercancel', 'pointerleave']) {
    exitZone.addEventListener(t, () => clearTimeout(exitTimer));
  }

  window.addEventListener('resize', () => { if (state !== 'picking') layout(); });

  // ---- finishing an item ----

  function celebrate() {
    if (state !== 'tracing') return;
    state = 'celebrating';
    clearTimeout(idleTimer);
    chime();
    fx.sweepStart = performance.now();
    later(300, spawnSparkles);
    later(SWEEP_MS - 150, () => { fx.glowStart = performance.now(); kickFx(); });
    later(HOLD_MS, () => art.classList.add('hide'));
    later(HOLD_MS + FADE_MS, () => { nextItem(); art.classList.remove('hide'); });
    kickFx();
  }

  function spawnSparkles() {
    if (!item) return;
    const now = performance.now();
    for (let i = 0; i < 16; i++) {
      const p = item.samples[Math.floor(Math.random() * item.samples.length)];
      fx.sparkles.push({
        x: p.x, y: p.y,
        dx: (Math.random() - 0.5) * 4,
        dy: -(3 + Math.random() * 6),
        r: 0.8 + Math.random() * 1.3,
        born: now + Math.random() * 600,
        life: 1600 + Math.random() * 900,
        light: Math.random() < 0.5,
      });
    }
    kickFx();
  }

  // ---- effects layer: start dot, colour sweep, glow, sparkles ----

  function kickFx() {
    if (fx.running) return;
    fx.running = true;
    requestAnimationFrame(tick);
  }

  const ease = (t) => t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;

  function tick(now) {
    const ctx = fxCtx;
    clear(ctx);
    if (!item) { fx.running = false; return; }
    toBox(ctx);
    let busy = false;

    // A slow, soft pulse where the first stroke begins, until she starts.
    if (state === 'tracing') {
      fx.dot += ((drawnYet ? 0 : 1) - fx.dot) * 0.06;
      if (fx.dot > 0.01) {
        busy = true;
        const s = item.strokes[0].pts[0], wave = Math.sin(now / 1000 * Math.PI);
        ctx.fillStyle = colour;
        ctx.globalAlpha = fx.dot * (0.2 + 0.1 * wave);
        ctx.beginPath();
        ctx.arc(s.x, s.y, 4.4 + 0.9 * wave, 0, TAU);
        ctx.fill();
        ctx.globalAlpha = fx.dot * 0.9;
        ctx.beginPath();
        ctx.arc(s.x, s.y, 2.1, 0, TAU);
        ctx.fill();
        ctx.globalAlpha = 1;
      }
    }

    if (fx.sweepStart) {
      const p = Math.max(0, Math.min(1, (now - fx.sweepStart) / SWEEP_MS));
      sweep = ease(p);
      drawGuide();
      if (p < 1) busy = true; else fx.sweepStart = 0;
    }

    if (fx.glowStart) {
      const g = (now - fx.glowStart) / GLOW_MS;
      if (g >= 1) fx.glowStart = 0;
      else {
        busy = true;
        ctx.save();
        ctx.globalAlpha = Math.sin(Math.max(0, g) * Math.PI) * 0.5;
        ctx.shadowColor = colour;
        ctx.shadowBlur = 22 * DPR;
        ctx.strokeStyle = colour;
        ctx.lineWidth = INK * 0.6;
        for (const s of item.strokes) ctx.stroke(s.path);
        ctx.restore();
      }
    }

    if (fx.sparkles.length) {
      busy = true;
      fx.sparkles = fx.sparkles.filter((p) => now - p.born < p.life);
      for (const p of fx.sparkles) {
        const t = (now - p.born) / p.life;
        if (t < 0) continue;
        ctx.globalAlpha = 0.9 * (t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8);
        ctx.fillStyle = p.light ? tint : colour;
        ctx.beginPath();
        ctx.arc(p.x + p.dx * t, p.y + p.dy * t, p.r, 0, TAU);
        ctx.fill();
      }
      ctx.globalAlpha = 1;
    }

    if (busy) requestAnimationFrame(tick);
    else { fx.running = false; clear(ctx); }
  }

  // ---- sound: one soft chime per finished item ----

  let audio = null, bus = null;

  function unlockAudio() {
    try {
      if (!audio) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        audio = new AC();
        bus = audio.createGain();
        // A soft echo, like a small room.
        const delay = audio.createDelay(1);
        delay.delayTime.value = 0.3;
        const damp = audio.createBiquadFilter();
        damp.type = 'lowpass';
        damp.frequency.value = 1600;
        const feedback = audio.createGain();
        feedback.gain.value = 0.3;
        const wet = audio.createGain();
        wet.gain.value = 0.35;
        bus.connect(audio.destination);
        bus.connect(delay);
        delay.connect(damp);
        damp.connect(feedback);
        feedback.connect(delay);
        damp.connect(wet);
        wet.connect(audio.destination);
      }
      wakeAudio();
    } catch (_) { audio = null; }
  }

  // iOS only lets sound start inside a tap, so every touch nudges the audio awake.
  function wakeAudio() {
    if (!audio || audio.state === 'running') return;
    try {
      audio.resume();
      const src = audio.createBufferSource();
      src.buffer = audio.createBuffer(1, 1, 22050);
      src.connect(audio.destination);
      src.start(0);
    } catch (_) { /* ignore */ }
  }

  // C major pentatonic, so any two notes sound gentle together.
  const NOTES = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5];

  function chime() {
    if (!audio) return;
    if (audio.state !== 'running') audio.resume();
    const i = Math.floor(Math.random() * (NOTES.length - 2));
    const t = audio.currentTime + 0.03;
    bell(NOTES[i], t, 0.1);
    bell(NOTES[i + 2], t + 0.16, 0.07);
  }

  function bell(freq, t, peak) {
    for (const [mult, share] of [[1, 1], [2, 0.25], [3, 0.08]]) {
      const osc = audio.createOscillator();
      osc.type = 'sine';
      osc.frequency.value = freq * mult;
      const env = audio.createGain();
      const end = t + 2.5 / mult;
      env.gain.setValueAtTime(0.0001, t);
      env.gain.exponentialRampToValueAtTime(peak * share, t + 0.02);
      env.gain.exponentialRampToValueAtTime(0.0001, end);
      osc.connect(env);
      env.connect(bus);
      osc.start(t);
      osc.stop(end + 0.05);
    }
  }

  // ---- helpers ----

  function mix(a, b, t) {
    const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
    const ch = (p, s) => (p >> s) & 255;
    const c = [16, 8, 0].map((s) => Math.round(ch(pa, s) + (ch(pb, s) - ch(pa, s)) * t));
    return '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
  }

  // Read-only peek for automated testing; the app never uses it.
  window.QuietTrace = {
    peek: () => ({
      state,
      item: item && item.cat + ':' + item.name,
      coverage: item ? covered / item.samples.length : 0,
      penSeen,
      lines: lines.length,
    }),
    guidePoints: () => item ? item.strokes.map((s) => s.pts.map((p) => [OX + p.x * S / 100, OY + p.y * S / 100])) : [],
  };

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').catch(() => { /* not fatal: the app still works online */ });
  }
})();
