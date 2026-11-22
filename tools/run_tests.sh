#!/usr/bin/env bash
# Runs the headless test suites. A suite fails if it exits non-zero, runs out
# of time, or prints a SCRIPT ERROR or a parse error. Full output goes to
# .test-logs/<suite>.log
#
#   tools/run_tests.sh                 # every suite
#   tools/run_tests.sh update modes    # just those
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LIMIT=400   # seconds per suite
ALL="core fight battle b3more b3menu b3powers b3puzzle b3modes b3net vehicles maps history modes net toyfight update"
suites="${*:-$ALL}"

# Runs a command, stopping it after $1 seconds. Uses `timeout` (or gtimeout,
# from Homebrew's coreutils) when there is one; older Macs have neither.
run_limited() {
	local secs=$1
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "$secs" "$@"
	elif command -v gtimeout >/dev/null 2>&1; then
		gtimeout "$secs" "$@"
	else
		"$@" &
		local pid=$!
		# a watchdog that stops it when time runs out (and quits as soon as it's done)
		(
			for ((i = 0; i < secs; i++)); do
				sleep 1
				kill -0 "$pid" 2>/dev/null || exit 0
			done
			kill -TERM "$pid" 2>/dev/null
		) &
		local dog=$!
		wait "$pid"
		local code=$?
		kill "$dog" 2>/dev/null
		wait "$dog" 2>/dev/null
		return $code
	fi
}

mkdir -p .test-logs
"$GODOT" --headless --path . --import >/dev/null 2>&1
failed=0
for suite in $suites; do
	if [ ! -f "tests/test_$suite.gd" ]; then
		echo "FAIL  $suite  (there's no tests/test_$suite.gd)"
		failed=1
		continue
	fi
	log=".test-logs/$suite.log"
	run_limited $LIMIT "$GODOT" --headless --path . -- --test=$suite >"$log" 2>&1
	code=$?
	# "ERROR: 1 resources still in use at exit" is Godot being chatty, not a failure
	errs=$(grep -cE "SCRIPT ERROR|Parse Error|PARSE ERROR" "$log" || true)
	summary=$(grep -E "^test_$suite:" "$log" | tail -1)
	if [ $code -ne 0 ] || [ "$errs" != "0" ] || [ -z "$summary" ]; then
		echo "FAIL  $suite  (${summary:-no summary}, exit code $code, $errs script/parse errors) — see $log"
		failed=1
	else
		echo "ok    $suite  ($summary)"
	fi
done
exit $failed
