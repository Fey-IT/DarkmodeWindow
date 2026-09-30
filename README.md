# DarkmodeWindow

**English** | [Deutsch](README.de.md)

A macOS app that turns **anything bright on your screen dark** – in any app. Place the window
over a white document, a web page without dark mode, a light-themed program, a PDF or a shared
screen in a video call, and it shows that area **dark** – as a smart dark mode rather than a
simple color inversion. Made for people for whom bright screens cause eye strain or pain.

It works with every app on the Mac because it does not depend on the app supporting dark mode:
it simply converts whatever is visible beneath the window. Video calls (Teams, Meet, Zoom) where
someone shares white PowerPoint slides are just one typical use case.

## Features

- **Smart Dark:** white backgrounds become dark gray (#161616), black text becomes light gray
  (#DEDEDE). Colors keep their hue (red stays red, blue stays blue).
- **Keep Dark Areas:** content that is already dark (dark app UI, videos, photos) is not
  inverted; text stays crisp.
- **Dim:** alternative without conversion that only reduces brightness.
- **Snap to Bright Area Automatically:** every 2 seconds, finds the largest bright area
  on screen (e.g. a white document or a shared presentation) and places the window exactly
  over it.
- **Attach to a window:** the overlay follows another app's window as it moves or resizes –
  meeting apps are suggested first, any other window can be chosen under “Other Windows”.
- Clicks inside the window go through to the app underneath, so you keep working normally;
  move the window via its title bar and frame.

The user interface is bilingual: German on German-language systems, English everywhere else.

## Usage

| Action | Where |
| --- | --- |
| Show/hide window | ⌃⌥⌘D, Dock icon, moon menu |
| Auto snap on/off | ⌃⌥⌘A, app menu “Window”, moon menu |
| Mode, brightness, attach to a window | moon icon in the menu bar |
| Quit | ⌘Q (after clicking the frame/title bar), right-click the Dock icon |

## Requirements

- macOS 15 or later
- Xcode Command Line Tools (`xcode-select --install`); full Xcode is not required
- **Screen Recording** permission (System Settings › Privacy & Security)

## Build and run

```bash
./scripts/build-app.sh
open ~/Applications/DarkmodeWindow.app
```

The script builds with Swift Package Manager, creates the app bundle at
`~/Applications/DarkmodeWindow.app` and signs it ad hoc. Intermediate files go to
`~/Library/Caches/DarkmodeWindow-build`.

**About the permission:** because of the ad-hoc signature, macOS treats every rebuilt version
as a new app. After a rebuild, remove DarkmodeWindow from the list in System Settings with
**–**, restart the app and grant the permission again. A fixed signing certificate avoids this:
`SIGN_ID="Certificate name" ./scripts/build-app.sh`.

## Testing the filter

```bash
./scripts/shader-preview.sh [screenshot.png] [output.png] [scale]
```

Renders an image (e.g. a screenshot of a slide) through the filter: original on top, result
below. Without input, a test slide is generated.

## How it works

ScreenCaptureKit captures the area beneath the window (excluding the app itself), and a Metal
shader converts it in the OKLab color space. Details, design decisions and known trade-offs are
in [CLAUDE.md](CLAUDE.md).

## License

MIT – see [LICENSE](LICENSE). © 2026 Fey IT GmbH
