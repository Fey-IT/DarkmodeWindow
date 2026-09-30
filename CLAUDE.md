# DarkmodeWindow

## Purpose
macOS app with a movable, resizable window that shows the screen content **behind** it –
dimmed or converted into a smart dark mode. Main use case: screen sharing in Teams / Google Meet /
Zoom with white PowerPoint slides. Target audience: people who depend on dark displays (e.g. light
sensitivity) – **avoiding brightness spikes has top priority** (no white flash on start, on slide
changes or on errors).

## Technical approach
- macOS cannot filter other apps' content "through" a window directly. Instead,
  **ScreenCaptureKit** captures the area beneath the window (own app excluded), a **Metal shader**
  converts the image, and the window displays the result.
- Requires the **Screen Recording** permission (System Settings › Privacy & Security).
- The window uses `sharingType = .none` so it never shows up in its own capture or in the user's
  own screen shares.
- "Dim" mode works without capturing (semi-transparent dark layer) and is the fallback while the
  permission is missing.

## Modes
1. **Dim** – adjustable brightness (slider).
2. **Smart Dark** – lightness-based inversion in the OKLab color space:
   - Lightness L is inverted along a curve; hue is preserved (red stays red, blue stays blue –
     unlike a plain color inversion).
   - Background becomes dark gray (~#161616) instead of pure black (Material Design guideline).
   - Text becomes light gray (~#DEDEDE) instead of pure white (less glare and halation).
   - Colors are slightly desaturated and gamut-fitted so they stay readable on dark backgrounds.
   - **Adaptive** (menu "Keep Dark Areas", on by default):
     1. "Bright" mask (OKLab L > ~0.85). 2. "Paper" mask = bright *and* its ~2 pt surrounding
        bright (erosion via mipmap – thin white text does not count as paper).
     3. Inversion is decided **per region (~24 pt mip level), never per pixel**:
        `t = max(smoothstep(0.02, 0.12, paperFraction_24pt) * gate, paperSelf)`.
     4. `gate`: dark pixels are only lightened if there is light on **two opposite sides**
        (left+right up to ~7.5 pt or above+below up to ~20 pt, `opposingLight`, step `inkOffset`
        ≈ 5 pt). Text always has that; the edge of a wide dark area next to a slide (Meet/Teams
        background) only on one side. A plain radius test produced a bright stripe there.
   - **Lesson learned:** per-pixel rules (colorfulness, edge and ink rules) produced double
     outlines, stripes through bold headlines and white edges because `t` varied within a glyph.
     Do not reintroduce them – `t` must be constant across a glyph.
   - Known trade-offs: small colored elements on slides (buttons, bars) are converted as well
     (darker); photo edges partially; a 1-px line at hard edges between slide and dark UI; the
     occasional speck in bold headlines.
   - Always check tuning with `./scripts/shader-preview.sh [screenshot.png] [out.png] [scale]`
     (original on top, result below; without input a test slide is generated).

## Features
- **Auto position** (toggle "Snap to Bright Area Automatically" in the app menu "Window", in the
  moon menu and via ⌃⌥⌘A; `AutoPositioner.swift`): every 2 s a tiny screenshot (4-pt grid, own
  app excluded); the largest connected bright area (luminance > 0.72, at least 160×100 pt, fill
  ratio ≥ 50 %) becomes the content area (+1 grid cell margin, jumps only on ≥ 6 pt change).
  When attached, it only searches inside the meeting window and attaching only controls
  visibility. Moving the window manually does **not** turn auto position off (by request: the
  window snaps back on the next search); it is only turned off via the toggle. Tested with Meet
  screenshots (normal and enlarged presentation).
- **Attach to meeting window:** the overlay follows a Teams/Zoom/Meet window's position and size.
  While attached it stays at level `.floating` (no flash when switching apps); if the target window
  is not visible, the overlay hides. Dragging the window detaches it; a plain click does not.
- **Activation:** the panel is a `nonactivatingPanel` (never steals focus from Teams); a click on
  the frame/title bar calls `NSApp.activate()` so the menu bar and ⌘Q belong to DarkmodeWindow.

## Decisions
- **Name:** DarkmodeWindow, bundle ID `de.fey-it.DarkmodeWindow`.
- **Distribution:** open source (MIT), everyone builds it themselves; no notarization, no App Store.
  Ad-hoc signing (the Screen Recording permission may have to be granted again after each
  rebuild; fix: a fixed certificate via `SIGN_ID`).
- **Controls:** thin dark frame with title bar for moving/resizing; the inner area is
  click-through (clicks go to Teams/Meet underneath). Global shortcut ⌃⌥⌘D shows/hides the window.
- **Dock app** (previously menu-bar only): quit via ⌘Q/Dock, clicking the Dock icon brings the
  window back. The moon icon in the menu bar holds mode, brightness and attach options. The ✕ in
  the window only hides it.
- **Photos:** no image detection; the adaptive mode keeps regions without light "paper" (dark UI,
  video tiles, photo interiors) unchanged. Real photo detection only if it proves necessary.
- **Language:** UI is bilingual via `L10n.t(german, english)` (`Localization.swift`): German on
  German systems, English otherwise. New UI strings always need both.

## Conventions
- Code, identifiers, comments and docs in English; `README.de.md` is the German README and must be
  kept in sync with `README.md`.
- The maintainer (Fey IT) communicates in German.
- Discuss larger decisions with the maintainer before implementing them.
- The app itself is dark (no light UI, including settings and dialogs).

## Tech stack
- Swift 6 (language mode 5), AppKit (NSPanel for the overlay), ScreenCaptureKit, Metal.
- **No Xcode required** (Command Line Tools only) → build via **Swift Package Manager**; the
  `.app` bundle is assembled by `scripts/build-app.sh` and signed ad hoc.
- Target: macOS 15+.
- Build products live outside the source folder (`~/Library/Caches/DarkmodeWindow-build`), so
  e.g. iCloud Drive does not sync intermediate files.

## Repository
- Public: **`github.com/Fey-IT/DarkmodeWindow`** (branch `main`, MIT license).

## Build & run
```bash
./scripts/build-app.sh          # builds and installs to ~/Applications/DarkmodeWindow.app
open ~/Applications/DarkmodeWindow.app
```
Test the English UI on a German system: `open ~/Applications/DarkmodeWindow.app --args -AppleLanguages "(en)"`.

## Code structure
- `Sources/DarkmodeWindow/AppDelegate.swift` – menus, shortcuts, wiring
- `OverlayController.swift` / `OverlayWindow.swift` – window, frame, click-through
- `CaptureController.swift` – ScreenCaptureKit stream for the area beneath the window. If the
  window extends past the screen edge, only the visible part is captured; that part
  (`coveredRect`) is drawn at the right place via the renderer's viewport (otherwise distorted).
- `Shaders.swift` – Metal source + `ShaderParams` (compiled at runtime since there is no offline
  metal compiler; the struct layout must match `Params` in the shader)
- `DarkFilter.swift` – GPU pipeline (copy frame, bright/paper masks + mipmaps, output), no view
- `Renderer.swift` – connects ScreenCaptureKit frames, DarkFilter and MTKView
- `AutoPositioner.swift` – periodic search for the largest bright area
- `WindowDocking.swift` – find and follow meeting windows
- `Localization.swift` – German/English UI strings
- `HotKey.swift`, `Settings.swift`
- `Tools/ShaderPreview/main.swift` – command-line preview of the filter (via `scripts/shader-preview.sh`)
