#!/bin/zsh
# Doppelklick startet "Gili Genting" mit der Godot-Engine.
cd "$(dirname "$0")/game"
GODOT="/Users/noahwiedemer/Downloads/Godot.app/Contents/MacOS/Godot"
[ -x "$GODOT" ] || GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --path . --fullscreen "$@"
