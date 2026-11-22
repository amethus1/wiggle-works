#!/usr/bin/env bash
# Publishes a new version of Wiggle Works on GitHub (a Release with the Windows
# .exe, the Mac .zip and SHA256SUMS.txt). Windows players get "✨ New version!"
# the next time the game starts, and one click updates it.
#
#   tools/release.sh 1.0.1 "New dinosaurs and fewer bugs"
#   tools/release.sh 1.0.1 "New dinosaurs and fewer bugs" --skip-tests
#
# Before changing anything it checks that gh is logged in and that git has
# nothing waiting to be committed. Only the version number may already be
# changed (say, by a release that stopped half-way). The commit it makes holds
# just the version number.
#
# Needs: git, the GitHub CLI (gh, logged in) and Godot 4.7.2 with its export templates.
set -eu
cd "$(dirname "$0")/.."

skip_tests=""
ver=""
notes=""
for a in "$@"; do
	if [ "$a" = "--skip-tests" ]; then
		skip_tests=1
	elif [ -z "$ver" ]; then
		ver="$a"
	elif [ -z "$notes" ]; then
		notes="$a"
	else
		echo "Too many words. Put the notes in quotes."
		exit 1
	fi
done
[ -n "$ver" ] || { echo 'usage: tools/release.sh VERSION "notes" [--skip-tests]'; exit 1; }
notes="${notes:-Updates and fixes.}"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must look like 1.2.3"; exit 1; }
if git rev-parse -q --verify "refs/tags/v$ver" >/dev/null; then
	echo "v$ver is already out. Pick a bigger number."
	exit 1
fi

# GitHub: is gh there and logged in?
command -v gh >/dev/null 2>&1 || { echo "This needs the GitHub command-line tool (gh): https://cli.github.com"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh isn't logged in to GitHub. Run: gh auth login"; exit 1; }

# Prints every change git sees, except the version lines this script writes.
VERSION_FILES='project\.godot|export_presets\.cfg'
VERSION_LINES='^[-+](config/version|application/(file_version|product_version|short_version|version))='
not_version() {
	git status --porcelain --untracked-files=all | grep -vE "^[ M][ M] ($VERSION_FILES)$" || true
	git diff HEAD -U0 -- project.godot export_presets.cfg | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ' | grep -vE "$VERSION_LINES" || true
}
other=$(not_version)
if [ -n "$other" ]; then
	echo "Commit or put away these changes first (only the version number may be changed already):"
	echo "$other"
	exit 1
fi

old=$(git show HEAD:project.godot | sed -n 's/^config\/version="\(.*\)"/\1/p')
echo "Wiggle Works $old -> $ver"

# the version number goes into the game and into the Windows/Mac file info
sed -i '' -e "s/^config\/version=.*/config\/version=\"$ver\"/" project.godot
sed -i '' \
	-e "s/^application\/file_version=.*/application\/file_version=\"$ver.0\"/" \
	-e "s/^application\/product_version=.*/application\/product_version=\"$ver.0\"/" \
	-e "s/^application\/short_version=.*/application\/short_version=\"$ver\"/" \
	-e "s/^application\/version=.*/application\/version=\"$ver\"/" \
	export_presets.cfg

if [ -z "$skip_tests" ]; then
	tools/run_tests.sh
fi
tools/export_all.sh
rm -rf build/release
mkdir -p build/release
cp "build/windows/Wiggle Works.exe" build/release/WiggleWorks-Windows.exe
cp "build/mac/Wiggle Works.zip" build/release/WiggleWorks-Mac.zip
(cd build/release && shasum -a 256 WiggleWorks-Windows.exe WiggleWorks-Mac.zip >SHA256SUMS.txt)

# the tests and the build mustn't have changed anything else
other=$(not_version)
if [ -n "$other" ]; then
	echo "The tests or the build changed these files. Check them and commit them, then run this again:"
	echo "$other"
	exit 1
fi
git add project.godot export_presets.cfg
if ! git diff --cached --quiet; then
	git commit -q -m "Wiggle Works $ver" -m "$notes"
fi
git tag "v$ver"
git push -q origin HEAD "v$ver"
gh release create "v$ver" build/release/WiggleWorks-Windows.exe build/release/WiggleWorks-Mac.zip build/release/SHA256SUMS.txt \
	--title "Wiggle Works $ver" --notes "$notes"
echo "Done: $(gh repo view --json url -q .url)/releases/tag/v$ver"
