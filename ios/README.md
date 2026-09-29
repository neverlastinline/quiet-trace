# Quiet Trace for iPad and iPhone

A native Swift version of [Quiet Trace](../README.md). It's the same calm, featureless game: pick a colour, then trace. It uses the same eight colours, the same 69 drawings, the same tracing check, the same celebration and the same chime. Nothing is on screen but the drawing.

## Why a native app and not a wrapper around the website

- **The App Store.** Apple tends to reject apps that are just a website in a frame (guideline 4.2, "minimum functionality"). A native app avoids that. It can also go in the **Kids** category.
- **Apple Pencil.** The app gets every Pencil sample at up to 240 Hz, pressure included, plus predicted touches that hide latency. The web app only sees what Safari passes on.
- **Staying in the game.** There's no status bar. The home indicator fades away, and a swipe in from any edge needs a second swipe before iOS acts on it. Guided Access still works too.
- **Sound.** The chime uses the "ambient" audio session. It follows the silent switch, never stops music that's already playing, and doesn't need a tap to unlock audio first.
- **Offline, always.** Everything is in the app, so there's no service worker and no need to visit once while online.

## What's the same, and what's different

Everything a child sees and does matches the web app:
- the colour picker
- the dotted guide with its pulsing start dot
- coverage (85%, or 65% followed by a 3-second pause)
- the colour sweep, glow and sparkles
- one chime per drawing
- the order of drawings (weighted categories, never the same category twice, shuffled bags)
- palm rejection: with Apple Pencil in use, fingers are ignored for 10 seconds, and with fingers, the touch that moves is the one that draws
- the hidden grown-up exit (hold the top-left corner for 3 seconds)

The numbers live in [`Tuning.swift`](QuietTraceKit/Sources/QuietTraceKit/Tuning.swift) and match `app.js`.

Small differences:
- The swatches have VoiceOver labels (the colour names). The tracing area reads as "Tracing, star" and allows direct interaction, so a VoiceOver user can draw.
- When a moving finger takes over from a resting hand, its line starts where the finger is now. The web app adds a small backwards zig-zag at that point.
- Works on iPhone as well as iPad, in any orientation.

## Running it

You need a Mac with **Xcode 16 or later**. The app runs on **iOS/iPadOS 16 or later**.

1. Open `ios/QuietTrace.xcodeproj`.
2. Pick an iPad simulator and press **Run** (⌘R).
3. To run it on your own iPad: select the **QuietTrace** target → **Signing & Capabilities** → choose your **Team**, change the **Bundle Identifier** to one you own if needed, plug the iPad in and press Run. A free Apple ID works for your own devices, but the app then expires after 7 days. A paid Apple Developer Program membership ($99/year) removes that limit and is needed for TestFlight and the App Store.

## How it's built

| Path | What it is |
|---|---|
| `QuietTraceKit/` | A Swift package with everything that isn't UIKit. It builds and tests on macOS and Linux. |
| `QuietTraceKit/Sources/QuietTraceKit/Library.swift` | Every drawing, as the same SVG path data as `shapes.js` |
| `…/PathData.swift`, `…/Guide.swift` | Reads SVG path data (arcs included), splits it into strokes and spaces guide points along them |
| `…/Tracer.swift` | Which touch is drawing, the child's lines, and how much of the guide they cover |
| `…/ItemPicker.swift` | What comes next |
| `…/Chime.swift` | Synthesises the chime sample by sample, like the web app's Web Audio graph |
| `QuietTrace/` | The UIKit app |
| `QuietTrace/GameViewController.swift` | The flow: colours → tracing → celebration → next drawing, plus the exit back |
| `QuietTrace/StageView.swift` | Guide layers, touch handling, start dot, sweep, glow and sparkles (Core Animation) |
| `QuietTrace/InkView.swift` | The child's lines. Finished lines go into a bitmap; only the live line is redrawn as it grows. |
| `QuietTrace/PickerView.swift` | The eight breathing colours |
| `QuietTrace/ChimePlayer.swift` | Plays the chime with AVAudioEngine |
| `QuietTraceUITests/` | Simulator tests that choose a colour, trace a square with real touches, and use the hidden exit |
| `scripts/web-reference.cjs` | Measures every drawing in a real browser and writes the fixture the parity tests compare against |

### Tests

```bash
# The core, on a Mac or in Docker on Linux
swift test --package-path ios/QuietTraceKit
docker run --rm -v "$PWD/ios/QuietTraceKit":/pkg -w /pkg swift:6.1-noble swift test

# Everything, including the simulator UI tests
xcodebuild test -project ios/QuietTrace.xcodeproj -scheme QuietTrace \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)'
```

The parity tests check that every guide point on iOS lands within 0.05 box units of the web app's. **If you change `shapes.js`, make the same change in `Library.swift` and refresh the fixture:**

```bash
NODE_PATH="$(npm root -g)" node ios/scripts/web-reference.cjs   # needs Playwright + Chromium
```

CI (`.github/workflows/ios.yml`) runs the core tests on Linux and macOS. On macOS it re-measures `shapes.js` in Chromium first, so a drawing changed in only one place fails the build. It then builds the app, runs the UI tests on an iPad simulator, and does an unsigned Release build for devices. Screenshots from the UI tests are saved as a workflow artifact.

## Getting it onto the App Store

1. **Apple Developer Program**: join at developer.apple.com ($99/year).
2. **Bundle ID**: set your own in the target's Signing & Capabilities. It is currently `io.github.neverlastinline.quiettrace`, and it can't change after the first upload.
3. **App Store Connect**: create the app record.
   - **Category:** Kids, age band *5 and under*. `Info.plist` already declares `public.app-category.kids-games`.
   - **Age rating:** 4+.
   - **App Privacy:** *Data Not Collected*. The app has no network code, analytics, ads or accounts, and `PrivacyInfo.xcprivacy` says so.
   - **Privacy policy URL:** required for every app and especially for Kids apps. One short page is enough, for example: *"Quiet Trace collects no data. It has no accounts, ads, analytics or tracking, makes no network connections, and stores nothing about you or your child."* It could live next to the web app on GitHub Pages.
   - **Screenshots:** 13-inch iPad and 6.9-inch iPhone, since the app supports both. The simulator's File → Save Screen works. Leaving the app iPad-only would remove the iPhone requirement: set *Targeted Device Family* to iPad only.
   - **Export compliance:** already answered in `Info.plist` (`ITSAppUsesNonExemptEncryption = NO`).
4. **Upload:** in Xcode, choose **Any iOS Device**, then Product → **Archive** → Distribute App → App Store Connect.
5. **TestFlight:** try it on a real iPad with Apple Pencil and a real child before submitting.
6. **Submit for review.** In the review notes, mention the hidden exit (hold the top-left corner for 3 seconds). Otherwise the reviewer won't find a way back to the colours.

## Roadmap

- [x] Port the game, with parity tests against the web app
- [x] Simulator UI tests and CI
- [ ] Play-test on a real iPad with Apple Pencil (pressure feel, palm rejection, latency)
- [ ] TestFlight with a few families
- [ ] App Store submission
- Possible native-only touches, each kept as quiet as the rest of the game: an Apple Pencil hover preview of the start dot on iPads that support hover, and haptic ticks on iPhone.
