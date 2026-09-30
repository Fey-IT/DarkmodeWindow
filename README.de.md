# DarkmodeWindow

[English](README.md) | **Deutsch**

macOS-App, die **alles Helle auf dem Bildschirm dunkel macht** – in jedem Programm. Das Fenster
über ein weißes Dokument, eine Webseite ohne Dark Mode, ein helles Programm, ein PDF oder einen
geteilten Bildschirm in einer Videokonferenz legen, und der Bereich erscheint **dunkel** – als
intelligenter Dark Mode statt simpler Farbumkehr. Gedacht für Menschen, denen helle Bildschirme
Augenschmerzen bereiten.

Die App funktioniert mit allen Programmen auf dem Mac, weil sie nicht darauf angewiesen ist, dass
ein Programm selbst einen Dark Mode hat: Sie wandelt einfach um, was unter dem Fenster zu sehen
ist. Videokonferenzen (Teams, Meet, Zoom), in denen jemand weiße PowerPoint-Folien teilt, sind nur
ein typischer Anwendungsfall.

## Was die App macht

- **Smart Dark:** Weißer Hintergrund wird dunkelgrau (#161616), schwarze Schrift hellgrau
  (#DEDEDE). Farben behalten ihren Farbton (Rot bleibt rot, Blau bleibt blau).
- **Dunkle Bereiche beibehalten:** Was schon dunkel ist (dunkle Programmoberflächen, Videos,
  Fotos), wird nicht umgekehrt; Schrift bleibt scharf.
- **Abdunkeln:** Alternative ohne Umwandlung, nur Helligkeit reduzieren.
- **Automatisch auf hellen Bereich ausrichten:** Sucht alle 2 Sekunden die größte helle Fläche
  auf dem Bildschirm (z. B. ein weißes Dokument oder eine geteilte Präsentation) und legt das
  Fenster passgenau darüber.
- **An ein Fenster andocken:** Das Overlay folgt dem Fenster eines anderen Programms, wenn es
  verschoben oder vergrößert wird – Meeting-Apps werden zuerst vorgeschlagen, jedes andere
  Fenster ist unter „Andere Fenster“ wählbar.
- Klicks in den Innenbereich gehen an das Programm darunter, man arbeitet also normal weiter;
  verschoben wird über Titelleiste und Rahmen.

Die Oberfläche ist zweisprachig: Deutsch auf deutschsprachigen Systemen, sonst Englisch.

## Bedienung

| Aktion | Wo |
| --- | --- |
| Fenster ein-/ausblenden | ⌃⌥⌘D, Dock-Symbol, Mond-Menü |
| Auto-Position an/aus | ⌃⌥⌘A, App-Menü „Fenster“, Mond-Menü |
| Modus, Helligkeit, Andocken | Mond-Symbol in der Menüleiste |
| Beenden | ⌘Q (nach Klick auf Rahmen/Titelleiste), Rechtsklick aufs Dock-Symbol |

## Voraussetzungen

- macOS 15 oder neuer
- Xcode Command Line Tools (`xcode-select --install`); ein volles Xcode ist nicht nötig
- Berechtigung **Bildschirmaufnahme** (Systemeinstellungen › Datenschutz & Sicherheit)

## Bauen und starten

```bash
./scripts/build-app.sh
open ~/Applications/DarkmodeWindow.app
```

Das Skript baut mit dem Swift Package Manager, legt das App-Bundle unter
`~/Applications/DarkmodeWindow.app` an und signiert es ad hoc. Zwischendateien liegen in
`~/Library/Caches/DarkmodeWindow-build`.

**Hinweis zur Berechtigung:** Wegen der Ad-hoc-Signatur sieht macOS jede neu gebaute Version
als neue App. Nach einem Neubau in den Systemeinstellungen den Eintrag DarkmodeWindow mit
**–** entfernen, App neu starten und die Berechtigung erneut erteilen. Mit einem festen
Signier-Zertifikat entfällt das: `SIGN_ID="Name des Zertifikats" ./scripts/build-app.sh`.

## Filter testen

```bash
./scripts/shader-preview.sh [screenshot.png] [ausgabe.png] [scale]
```

Rendert ein Bild (z. B. Screenshot einer Folie) durch den Filter: oben Original, unten Ergebnis.
Ohne Eingabe wird eine Testfolie erzeugt.

## Technik

ScreenCaptureKit nimmt den Bereich unter dem Fenster auf (eigene App ausgeschlossen), ein
Metal-Shader wandelt ihn im OKLab-Farbraum um. Details, Entscheidungen und bekannte
Kompromisse stehen in [CLAUDE.md](CLAUDE.md).

## Lizenz

MIT – siehe [LICENSE](LICENSE). © 2026 Fey IT GmbH
