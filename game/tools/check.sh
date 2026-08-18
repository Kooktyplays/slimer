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
echo "--- errors: $COUNT"
[ "$COUNT" -eq 0 ]
