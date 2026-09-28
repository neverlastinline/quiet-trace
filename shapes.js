/* Quiet Trace — the things to trace.
 *
 * Every item is a centreline drawing in a 100 × 100 box, written as SVG path
 * data. Use absolute commands only (M L H V C Q T A Z): each "M" starts a new
 * stroke, and strokes are measured separately.
 */
(function () {
  'use strict';

  // ---- helpers for drawings that are easier to generate than hand-write ----

  // A circle that starts at the top and runs anticlockwise, the way children
  // are taught to draw an "o".
  function circle(cx, cy, r) {
    return `M${cx} ${cy - r} A${r} ${r} 0 1 0 ${cx} ${cy + r} A${r} ${r} 0 1 0 ${cx} ${cy - r}`;
  }

  // A parametric curve as a polyline.
  function curve(fn, t0, t1, steps) {
    let d = '';
    for (let i = 0; i <= steps; i++) {
      const [x, y] = fn(t0 + (t1 - t0) * i / steps);
      d += (i ? ' L' : 'M') + x.toFixed(2) + ' ' + y.toFixed(2);
    }
    return d;
  }

  // A closed, bumpy ring (flower petals, tree tops): n points on a circle of
  // radius R joined by outward arcs of radius r.
  function puffy(cx, cy, R, n, r, startDeg) {
    const pts = [];
    for (let i = 0; i <= n; i++) {
      const a = (startDeg + 360 * i / n) * Math.PI / 180;
      pts.push([cx + R * Math.cos(a), cy + R * Math.sin(a)]);
    }
    let d = `M${pts[0][0].toFixed(2)} ${pts[0][1].toFixed(2)}`;
    for (let i = 1; i <= n; i++) d += ` A${r} ${r} 0 1 1 ${pts[i][0].toFixed(2)} ${pts[i][1].toFixed(2)}`;
    return d + ' Z';
  }

  // Straight rays around a centre.
  function rays(cx, cy, r0, r1, n, startDeg) {
    let d = '';
    for (let i = 0; i < n; i++) {
      const a = (startDeg + 360 * i / n) * Math.PI / 180;
      const c = Math.cos(a), s = Math.sin(a);
      d += ` M${(cx + r0 * c).toFixed(2)} ${(cy + r0 * s).toFixed(2)} L${(cx + r1 * c).toFixed(2)} ${(cy + r1 * s).toFixed(2)}`;
    }
    return d.trim();
  }

  // ---- the library ----

  const shapes = {
    circle: circle(50, 50, 40),
    square: 'M15 15 H85 V85 H15 Z',
    triangle: 'M50 12 L90 84 H10 Z',
    star: 'M50 10 L60.6 39.4 L91.8 40.4 L67.1 59.6 L75.9 89.6 L50 72 L24.1 89.6 L32.9 59.6 L8.2 40.4 L39.4 39.4 Z',
    heart: 'M50 27 C46 18 39 12 29 12 C18 12 8 20 8 34 C8 50 20 66 50 88 C80 66 92 50 92 34 C92 20 82 12 71 12 C61 12 54 18 50 27 Z',
    diamond: 'M50 8 L82 50 L50 92 L18 50 Z',
    oval: 'M50 22 A42 28 0 1 0 50 78 A42 28 0 1 0 50 22',
    moon: 'M62 12 A40 40 0 1 0 62 88 A44 44 0 0 1 62 12 Z',
  };

  const objects = {
    house: 'M14 52 L50 16 L86 52 M24 42 V88 H76 V42 M42 88 V64 H58 V88',
    sun: circle(50, 50, 19) + ' ' + rays(50, 50, 27, 41, 8, -90),
    fish: 'M12 50 C26 26 56 26 70 50 C56 74 26 74 12 50 Z M70 50 L90 32 V68 Z ' + circle(28, 45, 3),
    flower: puffy(50, 36, 20, 5, 12.5, -90) + ' ' + circle(50, 36, 7) + ' M50 69 V94 M50 84 Q62 70 76 72 Q68 88 50 84 Z',
    tree: puffy(50, 38, 18, 7, 9.5, -90) + ' M44 67 V90 M56 67 V90 M26 90 H74',
    apple: 'M50 30 C40 22 16 24 16 50 C16 74 34 90 44 88 C48 87 52 87 56 88 C66 90 84 74 84 50 C84 24 60 22 50 30 Z M50 30 Q50 18 56 10 M53 20 Q64 8 74 14 Q64 26 53 20 Z',
    balloon: 'M50 8 C66 8 80 20 80 38 C80 52 70 70 50 70 C30 70 20 52 20 38 C20 20 34 8 50 8 Z M50 70 C42 78 58 86 50 95',
    cloud: 'M20 72 A12 12 0 0 1 22 48 A16 16 0 1 1 50 32 A15 15 0 0 1 78 44 A13 13 0 0 1 80 72 Z',
    butterfly: 'M50 42 C40 18 12 12 12 32 C12 48 34 52 50 48 M50 42 C60 18 88 12 88 32 C88 48 66 52 50 48 M50 52 C36 52 20 62 24 76 C28 88 44 80 50 62 M50 52 C64 52 80 62 76 76 C72 88 56 80 50 62 M50 30 V78 M49 30 C46 20 42 16 36 14 M51 30 C54 20 58 16 64 14',
    boat: 'M12 62 H88 L76 80 H24 Z M50 62 V12 M50 16 L78 54 H50 M8 90 Q18 82 28 90 T48 90 T68 90 T88 90',
    car: 'M10 66 V54 Q10 46 18 46 H28 L38 30 H64 L76 46 H84 Q92 46 92 54 V66 Z M28 46 H76 M51 30 V46 ' + circle(30, 68, 9) + ' ' + circle(72, 68, 9),
    cat: 'M20 36 L22 12 L40 26 Q50 22 60 26 L78 12 L80 36 C88 50 86 70 72 80 Q50 92 28 80 C14 70 12 50 20 36 Z ' +
      circle(38, 50, 3.5) + ' ' + circle(62, 50, 3.5) +
      ' M46 62 H54 L50 67 Z M50 67 Q46 72 42 70 M50 67 Q54 72 58 70 M36 66 L6 62 M36 70 L6 76 M64 66 L94 62 M64 70 L94 76',
    umbrella: 'M10 50 A40 40 0 0 1 90 50 Q80 42 70 50 Q60 42 50 50 Q40 42 30 50 Q20 42 10 50 Z M50 50 V84 A7 7 0 0 1 36 84 M50 10 V4',
    icecream: 'M28 48 C18 48 18 34 30 34 C28 20 40 14 50 14 C60 14 72 20 70 34 C82 34 82 48 72 48 Z M30 48 L50 94 L70 48',
    rocket: 'M50 6 C64 18 66 40 64 70 H36 C34 40 36 18 50 6 Z ' + circle(50, 36, 7) +
      ' M36 54 L22 72 V82 L36 70 M64 54 L78 72 V82 L64 70 M42 70 Q44 84 50 94 Q56 84 58 70',
    leaf: 'M14 86 C14 42 40 14 86 14 C86 58 58 86 14 86 Z M8 92 L64 36',
    rainbow: 'M10 72 A40 40 0 0 1 90 72 M22 72 A28 28 0 0 1 78 72 M34 72 A16 16 0 0 1 66 72',
  };

  const letters = {
    A: 'M50 12 L22 88 M50 12 L78 88 M33 60 H67',
    B: 'M28 12 V88 M28 12 H50 A18 18 0 0 1 50 48 H28 M50 48 A20 20 0 0 1 50 88 H28',
    C: 'M81.8 24.1 A38 38 0 1 0 81.8 75.9',
    D: 'M28 12 V88 H44 C66 88 78 70 78 50 C78 30 66 12 44 12 Z',
    E: 'M74 12 H28 V88 H74 M28 50 H66',
    F: 'M74 12 H28 V88 M28 50 H66',
    G: 'M79 27 A36 36 0 1 0 86 56 H60',
    H: 'M26 12 V88 M74 12 V88 M26 50 H74',
    I: 'M50 12 V88 M34 12 H66 M34 88 H66',
    J: 'M44 12 H80 M64 12 V64 A18 18 0 0 1 28 64',
    K: 'M28 12 V88 M72 12 L30 52 L74 88',
    L: 'M28 12 V88 H72',
    M: 'M20 88 V12 L50 60 L80 12 V88',
    N: 'M24 88 V12 L76 88 V12',
    O: 'M50 12 A30 38 0 1 0 50 88 A30 38 0 1 0 50 12',
    P: 'M28 12 V88 M28 12 H50 A19 19 0 0 1 50 50 H28',
    Q: 'M50 12 A30 38 0 1 0 50 88 A30 38 0 1 0 50 12 M58 66 L80 92',
    R: 'M28 12 V88 M28 12 H50 A19 19 0 0 1 50 50 H28 M48 50 L74 88',
    S: 'M72 20 C64 11 38 9 31 22 C24 36 44 44 52 48 C62 53 76 60 70 76 C64 91 36 92 28 80',
    T: 'M20 12 H80 M50 12 V88',
    U: 'M26 12 V60 A24 24 0 0 0 74 60 V12',
    V: 'M20 12 L50 88 L80 12',
    W: 'M12 12 L30 88 L50 30 L70 88 L88 12',
    X: 'M24 12 L76 88 M76 12 L24 88',
    Y: 'M22 12 L50 50 L78 12 M50 50 V88',
    Z: 'M24 12 H76 L24 88 H76',
    0: 'M50 12 A26 38 0 1 0 50 88 A26 38 0 1 0 50 12',
    1: 'M36 26 L52 12 V88 M34 88 H70',
    2: 'M28 30 C28 18 40 12 50 12 C62 12 72 20 72 32 C72 46 58 56 28 88 H74',
    3: 'M28 20 C34 14 42 12 50 12 C62 12 70 20 70 30 C70 42 60 48 46 48 C62 48 74 56 74 68 C74 82 62 88 50 88 C40 88 32 84 26 78',
    4: 'M62 12 L22 64 H80 M62 12 V88',
    5: 'M72 12 H34 L30 46 C38 42 44 40 52 40 C66 40 74 52 74 64 C74 78 64 88 50 88 C40 88 32 84 26 78',
    6: 'M70 18 C64 13 58 12 52 12 C36 12 26 30 26 54 C26 76 36 88 50 88 C64 88 74 78 74 64 C74 50 64 42 50 42 C38 42 28 50 26 60',
    7: 'M24 12 H76 L42 88',
    8: 'M68 20 C62 13 56 12 50 12 C39 12 30 19 30 30 C30 40 40 44 50 48 C60 52 74 57 74 68 C74 80 63 88 50 88 C37 88 26 80 26 68 C26 57 40 52 50 48 C60 44 70 40 70 30 C70 26 69 23 68 20',
    9: 'M72 34 C72 21 62 12 50 12 C38 12 28 21 28 34 C28 47 38 56 50 56 C62 56 72 47 72 34 V88',
  };

  const squiggles = {
    wave: 'M6 50 Q17 22 28 50 T50 50 T72 50 T94 50',
    zigzag: 'M8 64 L20 36 L32 64 L44 36 L56 64 L68 36 L80 64 L92 36',
    loops: curve((t) => [10 + (80 / (8 * Math.PI)) * (t - Math.PI) - 8 * Math.sin(t), 54 - 22 * Math.cos(t)], Math.PI, 9 * Math.PI, 320),
    spiral: curve((t) => {
      const r = 2 + 40 * t / (6 * Math.PI);
      return [50 + r * Math.cos(t - Math.PI / 2), 50 + r * Math.sin(t - Math.PI / 2)];
    }, 0, 6 * Math.PI, 360),
    arches: 'M8 64 A10.5 22 0 0 1 29 64 A10.5 22 0 0 1 50 64 A10.5 22 0 0 1 71 64 A10.5 22 0 0 1 92 64',
    cups: 'M8 36 A10.5 22 0 0 0 29 36 A10.5 22 0 0 0 50 36 A10.5 22 0 0 0 71 36 A10.5 22 0 0 0 92 36',
    castle: 'M8 66 V38 H20 V66 H32 V38 H44 V66 H56 V38 H68 V66 H80 V38 H92 V66',
    infinity: curve((t) => {
      const k = 1 + Math.sin(t) ** 2;
      return [50 + 42 * Math.cos(t) / k, 50 + 64 * Math.sin(t) * Math.cos(t) / k];
    }, 0, 2 * Math.PI, 240),
  };

  const items = { shapes, objects, letters, squiggles };

  // ---- measuring ----

  // Splits an item into strokes and samples points along each one, every
  // `step` box units. Returns [{ d, len, pts: [{x, y}] }].
  let probe = null;
  function measure(d, step) {
    if (!probe) {
      const ns = 'http://www.w3.org/2000/svg';
      const svg = document.createElementNS(ns, 'svg');
      svg.setAttribute('width', '0');
      svg.setAttribute('height', '0');
      svg.style.cssText = 'position:absolute;visibility:hidden;pointer-events:none';
      probe = document.createElementNS(ns, 'path');
      svg.appendChild(probe);
      document.body.appendChild(svg);
    }
    return d.split(/(?=M)/).map((s) => s.trim()).filter(Boolean).map((sd) => {
      probe.setAttribute('d', sd);
      const len = probe.getTotalLength();
      const n = Math.max(1, Math.ceil(len / step));
      const pts = [];
      for (let i = 0; i <= n; i++) {
        const p = probe.getPointAtLength(len * i / n);
        pts.push({ x: p.x, y: p.y });
      }
      return { d: sd, len, pts };
    });
  }

  window.QT = { items, measure };
})();
