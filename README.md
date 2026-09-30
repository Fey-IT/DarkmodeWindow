# DarkmodeWindow

macOS-App für Teams-/Meet-/Zoom-Meetings, in denen jemand eine helle Präsentation
(weiße PowerPoint-Folien, helle Apps) teilt. Ein Fenster legt sich über den geteilten
Bereich und zeigt ihn **dunkel** an – als intelligenter Dark Mode statt simpler
Farbumkehr. Gedacht für Menschen, denen helle Bildschirme Augenschmerzen bereiten.

## Was die App macht

- **Smart Dark:** Weißer Hintergrund wird dunkelgrau (#161616), schwarze Schrift hellgrau
  (#DEDEDE). Farben behalten ihren Farbton (Rot bleibt rot, Blau bleibt blau).
- **Dunkle Bereiche beibehalten:** Dunkle Oberflächen (Meet-/Teams-UI, Videokacheln, Fotos)
  werden nicht umgekehrt; Schrift bleibt scharf.
- **Abdunkeln:** Alternative ohne Umwandlung, nur Helligkeit reduzieren.
- **Automatisch auf hellen Bereich ausrichten:** Sucht alle 2 Sekunden die größte helle Fläche
  (z. B. die geteilte Präsentation) und legt das Fenster passgenau darüber.
- **An Meeting-Fenster andocken:** Fenster folgt einem Teams-/Meet-/Zoom-Fenster.
- Klicks in den Innenbereich gehen an das Meeting-Fenster darunter; verschoben wird über
  Titelleiste und Rahmen.

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
