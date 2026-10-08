# Quiet Trace

**A quiet tracing game. Pick a colour. Trace. That's all.**

**Play it here:** https://neverlastinline.github.io/quiet-trace/

Quiet Trace is a deliberately featureless tracing game for young children. It has:
- no menus, levels, scores, timers or stars
- no words on screen
- no ads, accounts or tracking
- nothing to win and nothing to lose

Your child chooses a colour once. After that, soft dotted shapes appear one at a time. Each one gently fills with their colour when it's traced, then the next one drifts in. It carries on for as long as they want to play.

It's made for calm: warm paper tones, slow fades, and one soft chime when a shape is finished.

## What's inside
About 70 things to trace, in a random order that doesn't repeat until each group has been used up:
- **Shapes:** circle, square, triangle, star, heart, diamond, oval, moon
- **Things:** house, sun, fish, flower, tree, apple, balloon, cloud, butterfly, boat, car, cat, umbrella, ice cream, rocket, leaf, rainbow
- **Letters and numbers:** A–Z and 0–9
- **Patterns:** waves, zigzags, loops, a spiral, arches, cups, a castle and a figure-eight

## Setting it up on an iPad
1. Open https://neverlastinline.github.io/quiet-trace/ in **Safari**.
2. Tap **Share** → **Add to Home Screen** → **Add**.
3. Open Quiet Trace from its new home-screen icon **while you're still online**. The home-screen app keeps its own offline copy, separate from Safari's. After that first launch it runs full-screen like any other app, and it keeps working with no internet connection.

### Good to know
- **Apple Pencil works best.** Line thickness follows pencil pressure, and while the pencil is in use the game ignores a resting hand. Fingers and simple kids' styluses work too, starting about 10 seconds after the pencil is put down. With a finger or stylus, a hand resting on the screen doesn't get in the way: whichever touch moves is the one that draws.
- **Changing colour:** press and hold the **top-left corner** of the screen for 3 seconds to go back to the colours. Nothing on screen shows this, and it won't trigger while your child is drawing.
- **Dark mode:** a small sun/moon button in the top-right corner switches between the light and dark paper. It follows the device's setting until it's pressed, then remembers the choice.
- **Muting:** the chime follows the iPad's silent mode.
- **Keeping them in the game:** turn on **Guided Access** (Settings → Accessibility → Guided Access). Triple-click the top or side button while the game is open to lock the iPad to it.

## For developers
Plain HTML, CSS and JavaScript, with no build step and no dependencies.

| File | What it is |
|---|---|
| `index.html`, `styles.css` | The page and its styles |
| `app.js` | Colour picker, tracing loop, coverage check, animations and chime |
| `shapes.js` | Every drawing, as centreline SVG path data in a 100 × 100 box |
| `sw.js`, `manifest.webmanifest` | Offline support and home-screen install |
| `dev/gallery.html` | Shows every drawing with its guide points (e.g. `dev/gallery.html?cat=letters&size=200`) |

To run it locally:

```bash
python -m http.server 8080
```

Then open <http://localhost:8080>.

To add a drawing, add a path to the right group in `shapes.js`, then check it in the gallery. Each `M` starts a new stroke, and the first stroke's start gets the pulsing "begin here" dot.
