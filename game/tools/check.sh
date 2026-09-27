#!/bin/bash
# Boot the game headless for a moment and report only real problems.
# `--import` alone does not surface GDScript parse errors; booting does.
GODOT="/Users/tanavyedlapalli/Downloads/Godot.app/Contents/MacOS/Godot"
cd "$(dirname "$0")/.." || exit 1
OUT=$("$GODOT" --headless --path . --quit-after "${1:-90}" 2>&1)

# "resources still in use at exit" / "ObjectDB instances leaked" are filtered:
# the engine tears autoloads down after the audio server has already stopped
# releasing playbacks, so the music stream is always reported at shutdown.
# It is a shutdown-order artifact with no effect while the game is running.
FILTER='resources still in use at exit|ObjectDB instances leaked|core/io/resource.cpp|core/object/object.cpp'

echo "$OUT" | grep -E "SCRIPT ERROR|ERROR:|WARNING:|Parse Error|at: res://" \
  | grep -vE "$FILTER" | head -40
COUNT=$(echo "$OUT" | grep -E "SCRIPT ERROR|ERROR:" | grep -vcE "$FILTER")
echo "--- boot errors: $COUNT"

# Second stage: actually load the test harness.
#
# Booting the game never touches tests/, so a parse error there is invisible
# here - and a script that fails to load means the harness never calls quit(),
# so Godot spins forever with no output while this script happily reports zero
# errors. That exact combination cost an hour once. The timeout is the guard:
# the suite takes well under a minute, so anything approaching the limit is a
# hang, not slowness.
echo "--- loading the test harness"
# No `timeout` on macOS by default, so this is done by hand: run in the
# background, poll, and kill it if it overruns.
# Templated, not a bare `mktemp`. BSD mktemp with no template ignores TMPDIR and
# uses the Darwin per-user temp dir, which is not writable under a sandbox that
# has been handed an explicit TMPDIR - and the failure mode was this script
# reporting "No such file or directory" for the log it never created.
TESTLOG=$(mktemp "${TMPDIR:-/tmp}/slimer-tests.XXXXXX")
"$GODOT" --headless --path . -- tests > "$TESTLOG" 2>&1 &
TEST_PID=$!
WAITED=0
while kill -0 "$TEST_PID" 2>/dev/null; do
  sleep 2
  WAITED=$((WAITED + 2))
  if [ "$WAITED" -ge 150 ]; then
    kill -9 "$TEST_PID" 2>/dev/null
    TEST_STATUS=124
    break
  fi
done
[ -z "${TEST_STATUS:-}" ] && wait "$TEST_PID" 2>/dev/null && TEST_STATUS=0 || TEST_STATUS=${TEST_STATUS:-1}
TESTS=$(cat "$TESTLOG")
rm -f "$TESTLOG"

if [ "$TEST_STATUS" -eq 124 ]; then
  echo "    FAILED: the test suite hung. Almost always a parse error in"
  echo "            tests/ - the harness cannot quit if it never loaded."
  exit 1
fi
echo "$TESTS" | grep -E "Parse Error|Failed to load script" | head -10
if echo "$TESTS" | grep -qE "Parse Error|Failed to load script"; then
  echo "    FAILED: a script the tests depend on does not parse"
  exit 1
fi
echo "$TESTS" | grep -E "^checks run|^RESULT" | sed 's/^/    /'

[ "$COUNT" -eq 0 ] && echo "$TESTS" | grep -q "RESULT: PASS"
