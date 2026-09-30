# DarkmodeWindow

**English** | [Deutsch](README.de.md)

A macOS app for Teams, Meet and Zoom meetings where someone shares a bright presentation
(white PowerPoint slides, light-themed apps). A window sits on top of the shared area and
shows it **dark** – as a smart dark mode rather than a simple color inversion. Made for
people for whom bright screens cause eye strain or pain.

## Features

- **Smart Dark:** white backgrounds become dark gray (#161616), black text becomes light gray
  (#DEDEDE). Colors keep their hue (red stays red, blue stays blue).
- **Keep Dark Areas:** dark surfaces (Meet/Teams UI, video tiles, photos) are not inverted;
  text stays crisp.
- **Dim:** alternative without conversion that only reduces brightness.
- **Snap to Bright Area Automatically:** every 2 seconds, finds the largest bright area
  (e.g. the shared presentation) and places the window exactly over it.
- **Attach to Meeting Window:** the window follows a Teams/Meet/Zoom window.
- Clicks inside the window go through to the meeting window underneath; move it via the
  title bar and frame.

The user interface is bilingual: German on German-language systems, English everywhere else.

## Usage

| Action | Where |
| --- | --- |
| Show/hide window | ⌃⌥⌘D, Dock icon, moon menu |
| Auto snap on/off | ⌃⌥⌘A, app menu “Window”, moon menu |
| Mode, brightness, attach | moon icon in the menu bar |
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
