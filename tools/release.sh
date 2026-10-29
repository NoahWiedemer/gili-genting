#!/bin/bash
# Exports Gili Genting for Windows, macOS and Linux and publishes it as a GitHub release.
# The Double W Launcher looks for the newest release and offers it as an install or update.
#
#   bash tools/release.sh            build and publish
#   bash tools/release.sh --dry-run  only build the ZIPs in build/release
#
# Before publishing: raise config/version in game/project.godot (and short_version/version of
# the macOS preset in game/export_presets.cfg), add the release on top of release_notes.json,
# commit and push. The release is tagged v<VERSION> on the pushed commit.
# Needs Godot 4.7.2 with its export templates and the GitHub CLI (gh auth login); or set GODOT.
#
# What the launcher expects (keep it when changing this script):
#   Gili-Genting-windows.zip  Gili-Genting.exe
#   Gili-Genting-macos.zip    Gili-Genting.app
#   Gili-Genting-linux.zip    Gili-Genting.x86_64
#   changelog.json            release_notes.json, every version's notes for the launcher
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Gili-Genting"
VERSION="$(sed -nE 's/^config\/version="([0-9.]+)"/\1/p' game/project.godot)"
NOTES="release_notes.json"
TAG="v$VERSION"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

find_godot() {
	for place in "${GODOT:-}" /Applications/Godot.app "$HOME/Applications/Godot.app" "$HOME/Downloads/Godot.app" "$HOME/Desktop/Godot.app"; do
		[ -z "$place" ] && continue
		[ -d "$place" ] && place="$place/Contents/MacOS/Godot"
		[ -x "$place" ] && { echo "$place"; return; }
	done
	command -v godot && return
	local found
	found="$(mdfind 'kMDItemCFBundleIdentifier == "org.godotengine.godot"' 2>/dev/null | head -1)"
	[ -n "$found" ] && { echo "$found/Contents/MacOS/Godot"; return; }
	return 1
}
GODOT_BIN="$(find_godot)" || { echo "Godot nicht gefunden. GODOT=/Pfad/zu/Godot.app setzen."; exit 1; }
echo "Gili Genting $VERSION mit $("$GODOT_BIN" --version | tail -1)"

if [ $DRY = 0 ]; then
	gh auth status >/dev/null 2>&1 || { echo "Erst bei GitHub anmelden: gh auth login"; exit 1; }
	if gh release view "$TAG" >/dev/null 2>&1; then
		echo "Release $TAG gibt es schon. Erst die Version erhöhen."; exit 1
	fi
	if [ -z "$(git branch -r --contains HEAD 2>/dev/null)" ]; then
		echo "Der aktuelle Commit ist noch nicht gepusht. Erst committen und pushen."; exit 1
	fi
	[ -n "$(git status --porcelain --untracked-files=no)" ] && echo "Achtung: Es gibt nicht committete Änderungen; sie kommen mit ins Spiel."
fi

rm -rf build
mkdir -p build/windows build/macos build/linux build/release

export_one() { # preset, output
	echo "Exportiere $1 ..."
	"$GODOT_BIN" --headless --path game --export-release "$1" "$2" >"build/export-$1.log" 2>&1 || { tail -20 "build/export-$1.log"; exit 1; }
	[ -e "build/${2#../build/}" ] || [ -e "$2" ] || { echo "Export $1 hat nichts erzeugt (build/export-$1.log)"; exit 1; }
}
export_one Windows ../build/windows/$NAME.exe
export_one macOS ../build/macos/$NAME.zip
export_one Linux ../build/linux/$NAME.x86_64

echo "Packe ..."
(cd build/windows && zip -qr -X ../release/$NAME-windows.zip . -x '*.DS_Store')
(cd build/linux && zip -qr -X ../release/$NAME-linux.zip . -x '*.DS_Store')
# macOS: signed again (ad hoc), or the bundle would not start on Apple Silicon.
(cd build/macos && ditto -x -k $NAME.zip . && rm $NAME.zip)
codesign --force --deep --sign - "build/macos/Gili Genting.app"
ditto -c -k --keepParent "build/macos/Gili Genting.app" "build/release/$NAME-macos.zip"

cp "$NOTES" build/release/changelog.json
python3 - "$NOTES" "$VERSION" >build/release/notes.md <<'PY'
import json, sys
releases = json.load(open(sys.argv[1]))
release = next((r for r in releases if r["version"] == sys.argv[2]), releases[0])
for section in release.get("sections", []):
    print(f"### {section['title']}")
    for item in section["items"]:
        print(f"- {item}")
    print()
PY
TITLE="$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(next((x for x in r if x["version"]==sys.argv[2]), r[0]).get("title",""))' "$NOTES" "$VERSION")"

ls -lh build/release
if [ $DRY = 1 ]; then echo "Probelauf fertig: build/release"; exit 0; fi

echo "Veröffentliche $TAG ..."
gh release create "$TAG" --target "$(git rev-parse HEAD)" --title "$VERSION · $TITLE" --notes-file build/release/notes.md \
	build/release/$NAME-windows.zip build/release/$NAME-macos.zip build/release/$NAME-linux.zip build/release/changelog.json
echo "Fertig. Der Launcher bietet Gili Genting $VERSION ab sofort als Update an."
