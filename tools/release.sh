#!/usr/bin/env bash
# Publishes a new version of Wiggle Works on GitHub (a Release with the Windows
# .exe and the Mac .zip). Windows players get "✨ New version!" the next time
# the game starts, and one click updates it.
#
#   tools/release.sh 1.0.1 "New dinosaurs and fewer bugs"
#   tools/release.sh 1.0.1 "New dinosaurs and fewer bugs" --skip-tests
#
# Needs: git, the GitHub CLI (gh, logged in) and Godot 4.7.2 with its export templates.
set -eu
cd "$(dirname "$0")/.."
ver="${1:-}"
[ -n "$ver" ] || { echo 'usage: tools/release.sh VERSION "notes" [--skip-tests]'; exit 1; }
notes="${2:-Updates and fixes.}"
skip="${3:-}"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must look like 1.2.3"; exit 1; }
if git rev-parse -q --verify "refs/tags/v$ver" >/dev/null; then
	echo "v$ver is already out. Pick a bigger number."
	exit 1
fi
old=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
echo "Wiggle Works $old -> $ver"

# the version number goes into the game and into the Windows/Mac file info
sed -i '' -e "s/^config\/version=.*/config\/version=\"$ver\"/" project.godot
sed -i '' \
	-e "s/^application\/file_version=.*/application\/file_version=\"$ver.0\"/" \
	-e "s/^application\/product_version=.*/application\/product_version=\"$ver.0\"/" \
	-e "s/^application\/short_version=.*/application\/short_version=\"$ver\"/" \
	-e "s/^application\/version=.*/application\/version=\"$ver\"/" \
	export_presets.cfg

if [ "$skip" != "--skip-tests" ]; then
	tools/run_tests.sh
fi
tools/export_all.sh
rm -rf build/release
mkdir -p build/release
cp "build/windows/Wiggle Works.exe" build/release/WiggleWorks-Windows.exe
cp "build/mac/Wiggle Works.zip" build/release/WiggleWorks-Mac.zip

git add -A
if ! git diff --cached --quiet; then
	git commit -q -m "Wiggle Works $ver" -m "$notes"
fi
git tag "v$ver"
git push -q origin HEAD "v$ver"
gh release create "v$ver" build/release/WiggleWorks-Windows.exe build/release/WiggleWorks-Mac.zip \
	--title "Wiggle Works $ver" --notes "$notes"
echo "Done: $(gh repo view --json url -q .url)/releases/tag/v$ver"
