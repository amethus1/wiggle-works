#!/usr/bin/env bash
# Builds Wiggle Works for Mac (.zip with the .app) and Windows (one .exe) into build/.
# Needs Godot 4.7.2's export templates (Godot: Editor > Manage Export Templates).
#
#   tools/export_all.sh
#   GODOT=/path/to/godot tools/export_all.sh
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p build/mac build/windows
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
for p in "Mac|build/mac/Wiggle Works.zip" "Windows|build/windows/Wiggle Works.exe"; do
	IFS='|' read -r name out <<<"$p"
	echo "Exporting $name -> $out"
	"$GODOT" --headless --path . --export-release "$name" "$out" 2>&1 | grep -E "ERROR" || true
	[ -f "$out" ] || { echo "  $name export failed"; exit 1; }
done
ls -lh build/mac build/windows
