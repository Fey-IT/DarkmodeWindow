# DarkmodeWindow

## Zweck
macOS-App mit einem frei verschiebbaren, größenveränderbaren Fenster, das den Bildschirminhalt
**dahinter** anzeigt – aber abgedunkelt oder in einen intelligenten Dark Mode umgewandelt.
Hauptanwendungsfall: Bildschirmfreigaben in Teams / Google Meet mit weißen PowerPoint-Folien.
Zielgruppe sind Menschen, die auf dunkle Darstellung angewiesen sind (z. B. Lichtempfindlichkeit) –
**Helligkeitsspitzen vermeiden hat höchste Priorität** (kein weißes Aufblitzen beim Start,
beim Folienwechsel oder bei Fehlern).

## Technischer Ansatz
- macOS kann Inhalte anderer Apps nicht direkt "durch ein Fenster hindurch" filtern.
  Deshalb: **ScreenCaptureKit** nimmt den Bereich unter dem Fenster auf (eigene App-Fenster
  ausgeschlossen), ein **Metal/Core-Image-Filter** wandelt das Bild um, das Fenster zeigt das Ergebnis.
- Benötigt die Berechtigung **Bildschirmaufnahme** (Systemeinstellungen › Datenschutz & Sicherheit).
- Eigenes Fenster mit `sharingType = .none`, damit es nie in der eigenen Aufnahme oder in
  eigenen Bildschirmfreigaben auftaucht.
- Modus "Abdunkeln" funktioniert auch ohne Aufnahme (halbtransparente dunkle Fläche) – dient als
  Fallback, solange die Berechtigung fehlt.

## Modi
1. **Abdunkeln** – Helligkeit regelbar (Schieberegler).
2. **Smart Dark** – helligkeitsbasierte Umkehrung im OKLab/OKLCH-Farbraum:
   - Helligkeit L wird über eine Kurve umgekehrt, Farbton (Hue) bleibt erhalten
     (rot bleibt rot, blau bleibt blau – anders als bei simpler Farbinvertierung).
   - Hintergrund wird nicht reines Schwarz, sondern ca. #121212–#1E1E1E (Material-Design-Richtlinie).
   - Text wird nicht reines Weiß, sondern ca. #E0E0E0 (weniger Blendung, weniger Überstrahlen).
   - Gesättigte Farben werden leicht entsättigt/aufgehellt, damit sie auf dunklem Grund lesbar bleiben
     (Kontrast min. WCAG AA 4.5:1 anstreben).
   - **Adaptiv** (Menü „Dunkle Bereiche beibehalten“, Standard an):
     1. Maske „hell“ (OKLab L > ~0.85), 2. Maske „Papier“ = hell *und* ~2 pt Umgebung hell
        (Erosion über Mipmap – dünne weiße Schrift zählt nicht als Papier).
     3. Umkehr-Entscheidung **pro Region (~24 pt Mipmap-Stufe), nie pro Pixel**:
        `t = max(smoothstep(0.02, 0.12, PapierAnteil_24pt) * gate, PapierSelbst)`.
     4. `gate`: dunkle Pixel werden nur aufgehellt, wenn auf **zwei gegenüberliegenden Seiten**
        Helles ist (links+rechts bis ~7,5 pt oder oben+unten bis ~20 pt, `opposingLight`, Abstand
        `inkOffset` ≈ 5 pt). Schrift hat das immer; der Rand einer breiten dunklen Fläche neben einer
        Folie (Meet-/Teams-Hintergrund) nur einseitig. Vorher (reiner Umkreis-Test) entstand dort ein
        heller Streifen. Rest: 1-px-Linie an solchen Kanten, vereinzelte Pünktchen in fetten Titeln.
- **Auto-Position** (Schalter „Automatisch auf hellen Bereich ausrichten“ im App-Menü „Fenster“,
  im Mond-Menü und per ⌃⌥⌘A; `AutoPositioner.swift`):
  alle 2 s ein Mini-Screenshot (4-pt-Raster, eigene App ausgeschlossen), größte zusammenhängende
  helle Fläche (Luminanz > 0.72, mind. 160×100 pt, Füllgrad ≥ 50 %) → Inhaltsbereich wird darauf
  gelegt (+1 Rasterzelle Rand, Sprung erst ab 6 pt Abweichung). Angedockt: Suche nur im
  Meeting-Fenster, Andocken steuert dann nur die Sichtbarkeit. Manuelles Verschieben schaltet
  Auto-Position **nicht** aus (gewünscht: Fenster springt beim nächsten Suchlauf zurück); aus nur
  über das Menü. Ein bloßer Klick auf den Rahmen löst auch kein Andocken mehr (nur echtes Ziehen). Getestet mit Meet-Screenshots (normale und vergrößerte Präsentation).
- **Aktivierung:** Das Panel ist `nonactivatingPanel` (nimmt Teams nicht den Fokus); ein Klick auf
  Rahmen/Titelleiste ruft `NSApp.activate()` auf, damit Menüleiste und ⌘Q zu DarkmodeWindow gehören.
   - **Lehre aus 2026-09-24:** Pixelgenaue Regeln (Farbigkeit, Kanten-, Tintenregeln) erzeugten
     Doppelkonturen, Streifen durch fette Überschriften und weiße Ränder, weil `t` innerhalb eines
     Glyphs variierte. Nicht wieder einführen – `t` muss über einen Buchstaben hinweg konstant sein.
   - Bekannte Kompromisse: kleine farbige Elemente auf Folien (Knöpfe, Balken) werden mit umgewandelt
     (dunkler), Ränder von Fotos teilweise; ~10–20 pt heller Saum an der Kante Folie/dunkle UI.
   - Tuning immer mit `./scripts/shader-preview.sh [screenshot.png] [out.png] [scale]` prüfen
     (oben Original, unten Ergebnis; ohne Eingabe wird eine Testfolie erzeugt).

## Tech-Stack
- Swift 6, SwiftUI + AppKit (NSWindow/NSPanel für das Overlay), ScreenCaptureKit, Metal/Core Image.
- **Kein Xcode installiert** (nur Command Line Tools) → Build per **Swift Package Manager**,
  `.app`-Bundle wird per Skript (`scripts/build-app.sh`) zusammengebaut und ad-hoc signiert.
- Ziel-System: macOS 15+.
- Build-Ordner liegt außerhalb des Quellordners (`~/Library/Caches/DarkmodeWindow-build`), damit
  z. B. iCloud Drive keine Zwischendateien synchronisiert.

## Konventionen
- Projektsprache **Deutsch** (UI-Texte, Doku, Absprachen); Code, Bezeichner und Code-Kommentare auf Englisch.
- Vor größeren Entscheidungen erst mit dem Maintainer abstimmen, dann umsetzen.
- Die App selbst ist dunkel gestaltet (kein helles UI, auch nicht in Einstellungen/Dialogen).

## Entscheidungen (abgestimmt am 2026-09-24)
- **Name:** DarkmodeWindow, Bundle-ID `de.fey-it.DarkmodeWindow`.
- **Verteilung:** Open Source (MIT), jeder baut selbst; keine Notarisierung, kein App Store.
  Signierung ad hoc (Bildschirmaufnahme-Berechtigung muss nach jedem Neubau ggf. neu erteilt
  werden; Abhilfe: festes Zertifikat per `SIGN_ID`).
- **Bedienung:** schmaler dunkler Rahmen mit Titelleiste zum Verschieben/Größe ändern;
  Innenbereich ist klick-durchlässig (Klicks gehen an Teams/Meet darunter).
  Globales Tastenkürzel ⌃⌥⌘D blendet das Fenster ein/aus.
- **Dock-App** (seit 2026-09-24, vorher reine Menüleisten-App): normales Beenden per ⌘Q/Dock,
  Klick aufs Dock-Symbol holt das Fenster zurück. Das Mond-Symbol in der Menüleiste bleibt für
  Modus, Helligkeit und Andocken. Das ✕ im Fenster blendet nur aus.
- **Fotos (entschieden von Claude):** Version 1 nutzt einen *adaptiven* Modus statt
  Bilderkennung: Invertiert wird nur, wo die Umgebung (grobe Mipmap-Stufen) hell ist.
  Dunkle Bereiche (Teams-UI, dunkle Fotos, Videokacheln) bleiben unverändert.
  Echte Fotoerkennung erst, wenn sich das in der Praxis als nötig erweist.
- **Andocken:** Overlay kann sich an ein Teams-/Zoom-/Meet-Fenster heften und folgt dessen
  Position/Größe. Angedockt bleibt es auf Ebene `.floating` (kein Aufblitzen beim App-Wechsel);
  ist das Zielfenster nicht sichtbar, wird das Overlay ausgeblendet. Manuelles Verschieben löst
  das Andocken.

## Repository
- Öffentlich: **`github.com/Fey-IT/DarkmodeWindow`** (Branch `main`, Lizenz MIT).

## Build & Start
```bash
./scripts/build-app.sh          # baut und installiert nach ~/Applications/DarkmodeWindow.app
open ~/Applications/DarkmodeWindow.app
```
Build-Zwischendateien liegen in `~/Library/Caches/DarkmodeWindow-build` (nicht in iCloud).

## Code-Struktur
- `Sources/DarkmodeWindow/AppDelegate.swift` – Menüleiste, Tastenkürzel, Verdrahtung
- `OverlayController.swift` / `OverlayWindow.swift` – Fenster, Rahmen, Klick-Durchlässigkeit
- `CaptureController.swift` – ScreenCaptureKit-Stream für den Bereich unter dem Fenster.
  Ragt das Fenster über den Bildschirmrand, wird nur der sichtbare Teil aufgenommen; dieser Teil
  (`coveredRect`) wird im Renderer per Viewport an die richtige Stelle gezeichnet (sonst Verzerrung).
- `Shaders.swift` – Metal-Quelltext + `ShaderParams` (wird zur Laufzeit kompiliert, da kein
  Xcode/metal-Compiler vorhanden; Struct-Layout muss zu `Params` im Shader passen)
- `DarkFilter.swift` – GPU-Pipeline (Frame kopieren, Papier-Maske + Mipmaps, Ausgabe), ohne View
- `Renderer.swift` – verbindet ScreenCaptureKit-Frames, DarkFilter und MTKView
- `Tools/ShaderPreview/main.swift` – Kommandozeilen-Vorschau des Filters (über `scripts/shader-preview.sh`)
- `WindowDocking.swift` – Meeting-Fenster finden und verfolgen
- `HotKey.swift`, `Settings.swift`
