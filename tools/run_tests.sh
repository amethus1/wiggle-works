#!/usr/bin/env bash
# Runs the headless test suites. A suite fails if it exits non-zero or prints
# a SCRIPT ERROR. Full output goes to .test-logs/<suite>.log
#
#   tools/run_tests.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
mkdir -p .test-logs
"$GODOT" --headless --path . --import >/dev/null 2>&1
failed=0
for suite in core fight battle b3more b3net vehicles maps history modes net update; do
	log=".test-logs/$suite.log"
	timeout 400 "$GODOT" --headless --path . -- --test=$suite >"$log" 2>&1
	code=$?
	errs=$(grep -c "SCRIPT ERROR" "$log" || true)
	summary=$(grep -E "^test_$suite:" "$log" | tail -1)
	if [ $code -ne 0 ] || [ "$errs" != "0" ]; then
		echo "FAIL  $suite  ($summary, $errs script errors) — see $log"
		failed=1
	else
		echo "ok    $suite  ($summary)"
	fi
done
exit $failed
