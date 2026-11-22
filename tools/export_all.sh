#!/usr/bin/env bash
# Builds Wiggle Works for Mac (.zip with the .app) and Windows (one .exe) into build/.
# Needs Godot 4.7.2's export templates (Godot: Editor > Manage Export Templates).
# Stops with an error if Godot reports a failed export; the full Godot output
# for each build is in build/export-<name>.log
#
#   tools/export_all.sh
#   GODOT=/path/to/godot tools/export_all.sh
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
builds=("Mac|build/mac/Wiggle Works.zip" "Windows|build/windows/Wiggle Works.exe")
mkdir -p build/mac build/windows
# old builds go first, so one can never pass for a new one (even if a later export fails)
for p in "${builds[@]}"; do
	rm -f "${p#*|}"
done
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
for p in "${builds[@]}"; do
	IFS='|' read -r name out <<<"$p"
	log="build/export-$name.log"
	echo "Exporting $name -> $out"
	code=0
	"$GODOT" --headless --path . --export-release "$name" "$out" >"$log" 2>&1 || code=$?
	grep -E "ERROR" "$log" || true
	if [ "$code" -ne 0 ] || [ ! -s "$out" ]; then
		echo "  $name export failed (Godot exit code $code) - see $log"
		exit 1
	fi
done
ls -lh build/mac build/windows
