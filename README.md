# Gili Genting – The Island of Chicken

Ein HD-2D-Pixel-RPG in Godot 4.7 nach der Geschichte „Gili Genting“.
Du spielst ein Huhn ohne Erinnerung, das auf dem Weg zu seiner eigenen Schlachtung die Menschen der Insel abschlachtet. Schwarzer Humor, rundenbasierte Kämpfe im Stil der alten Final-Fantasy-Teile.

## Starten

- Doppelklick auf `start_game.command`, oder:
- `/Users/noahwiedemer/Downloads/Godot.app/Contents/MacOS/Godot --path game`
- Zum Bearbeiten: Godot öffnen → Projekt importieren → `game/project.godot`

## Steuerung

| Aktion | Tastatur | Gamepad |
|---|---|---|
| Laufen | WASD / Pfeile | Stick / D-Pad |
| Rennen | Shift | X |
| Interagieren / Bestätigen | E / Enter / Leertaste | A |
| Zurück | Q / Esc / Backspace | B |
| Menü | Tab / M / C | Y |
| Vollbild | F11 | |

Tipp: Schlafende Gegner („z Z“) kannst du anschleichen (nicht rennen) und überraschen.

## Inhalt

- **5 Kapitel + Epilog:** Strand → Dorf der Verbannten → Verlassene Steppe → (Traum im weißen Raum) → Klippe der Aussichtslosen → Hof von Bauer Made → Sonnenfinsternis.
- **Charakter-Editor:** Name + Klasse (Krieger, Magier, Heiler, Tank, Assassine). Die Klasse ändert Aussehen, Werte und Skilltree.
- **Team:** max. 3 Hühner. 4 Gefährten (Jimmy, Vian, Nugget, Madame Paprika) können aufgenommen und wieder entlassen werden. XP werden auf die Team-Slots aufgeteilt, jeder Slot levelt einzeln; wer in einen Slot kommt, übernimmt dessen Level. Ein Slot, der zum ersten Mal besetzt wird, holt einmalig auf (max. 2 Level unter dir).
- **Grafik:** HD-2D – 3D-Diorama-Welt mit Pixel-Sprites, Tilt-Shift-Tiefenschärfe, dynamisches Licht (Laternen, Lagerfeuer, Fenster, Kristalle), Wolkenschatten, gemalte Panorama-Hintergründe im Kampf. Bewusst „glatte“ 3D-Effekte brechen den Pixelstil: Blüten, Regen, Wind, Glühwürmchen, Schmetterlinge, Federn & Blut im Kampf.
- **Skilltree:** pro Klasse 3 Zweige × 3 Stufen, Punkte hängen am Slot-Level.
- **Ausrüstung:** Waffe, Rüstung, Talisman. Essen heilt und gibt Buffs für die nächsten Kämpfe.
- **Kampf:** Befehle für alle wählen, dann handeln alle nach Tempo. Statuseffekte (Gift, Blutung, Betäubung, Blind, Spott …), Bosse: Buchmacher Benny, Der Wolf, Bauer Made, Der Schlachter.
- **Nebenquests:** Opa Kuras Strand, Muttermilch (Kuh & Kalb), Pilzfreunde, Lieselottes Punkte (Hof) – und ein toter Hai in einem Brunnen.
- **Geheimnisse & Rätsel:** Gezeitensteine am Strand (→ Gezeitengrotte), Laternen-Rätsel im Dorf (→ Keller der Hexe), eine Schatzkarte, die in die Steppe führt.
- **Shop:** Tokés Schwarzmarkt mit Kaufen/Verkaufen; das Sortiment wächst mit der Story, manche Ausrüstung gibt es nur dort.

## Projektstruktur

```
game/
  autoload/   data.gd (Klassen, Skills, Items, Gegner), game.gd (Spielstand), audio.gd, ui.gd (Dialoge, HUD, Fades)
  story/      story.gd – alle Story- und Quest-Events
  maps/       Map-Definitionen (prozedural „gemalt“ mit painter.gd) + Innenräume als ASCII
  world/      Terrain-Mesh-Builder, Häuser, Spieler, NPCs, Gegner, Licht & 3D-Wetter
  battle/     Kampfsystem, Kampfeinheiten, Kampf-UI
  ui/         Titel, Charakter-Editor, Menü, Shop, Game Over
  shaders/    Sprite-Shader (Wind, Hit-Flash, Dither-Fade), Wasser-Shader
  assets/     Sprites, Texturen, Effekte, UI, Fonts, Musik & SFX
tools/        Python-Generatoren für Sprites, Texturen, Fonts, Audio
art_src/      Rohbilder (Codex) und Vorschauen
```

## Entwickler-Tests

```bash
cd game
# kompletter automatischer Durchlauf aller Kapitel (Kämpfe, Dialoge, Menüs)
Godot --path . -- --story --auto
# simulierte Tastatureingaben (Laufen, Dialog, Kampfmenü, Pausenmenü)
Godot --path . -- --inputtest
# Screenshot einer Map
Godot --path . -- --shot dorf
```
