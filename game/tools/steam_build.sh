#!/bin/bash
# Build Slimer into the layout SteamPipe expects, and optionally upload.
#
#   ./tools/steam_build.sh                 build only
#   ./tools/steam_build.sh <steam-login>   build, then upload via steamcmd
#
# Produces:
#   build/steam/windows/Slimer.exe
#   build/steam/macos/Slimer.app
#   build/steam/linux/Slimer.x86_64
#
# Each platform gets its own depot, so each lives in its own content root.
# Steam does not want the whole build/ tree - only the files that ship.

set -u
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
OUT="../build/steam"
LOGIN="${1:-}"
FAILED=0

if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT (override with GODOT=/path/to/Godot)"
  exit 1
fi

# Same preset-name resolution as build.sh: opening the project in the editor
# can rename a preset to its platform name.
resolve_preset() {
  local wanted="$1"
  grep -q "^name=\"$wanted\"$" export_presets.cfg && { echo "$wanted"; return; }
  grep "^name=\"" export_presets.cfg | sed 's/name="\(.*\)"/\1/' \
    | grep -i "^$wanted" | head -1
}

export_to() {
  local wanted="$1" path="$2" label="$3"
  local preset
  preset=$(resolve_preset "$wanted")
  if [ -z "$preset" ]; then
    echo "    FAILED: no export preset named '$wanted'"; FAILED=1; return
  fi
  mkdir -p "$(dirname "$path")"
  echo "==> $label"
  local log
  log=$("$GODOT" --headless --path . --export-release "$preset" "$path" 2>&1 \
        | sed 's/\x1b\[[0-9;]*m//g')
  if echo "$log" | grep -qE "^ERROR|Project export .* failed" || [ ! -e "$path" ]; then
    echo "$log" | grep -E "^ERROR" | sed 's/^/    /'
    echo "    FAILED: $label"; FAILED=1
    return
  fi
  echo "$log" | grep -E "^WARNING" | grep -v "completed with warnings" \
    | sort -u | sed 's/^/    warning: /'
  echo "    ok: $path"
}

rm -rf "$OUT"
export_to "Windows" "$OUT/windows/Slimer.exe"     "Windows depot"
export_to "macOS"   "$OUT/macos/Slimer.app"       "macOS depot"
export_to "Linux"   "$OUT/linux/Slimer.x86_64"    "Linux depot"
chmod +x "$OUT/linux/Slimer.x86_64" 2>/dev/null

echo
echo "depot contents:"
du -sh "$OUT"/* 2>/dev/null

if [ "$FAILED" -ne 0 ]; then
  echo "one or more exports failed - not uploading"
  exit 1
fi

if grep -q "APPID_HERE" steam/app_build.vdf; then
  echo
  echo "steam/app_build.vdf still has placeholder IDs."
  echo "Fill in your App ID and the three depot IDs from Steamworks first."
  exit 0
fi

if [ -z "$LOGIN" ]; then
  echo
  echo "Built. To upload:"
  echo "  steamcmd +login <account> +run_app_build \\"
  echo "    \"$(cd .. && pwd)/game/steam/app_build.vdf\" +quit"
  exit 0
fi

if ! command -v steamcmd >/dev/null 2>&1; then
  echo "steamcmd not on PATH - install the Steamworks SDK content builder first."
  exit 1
fi

echo
echo "==> uploading as $LOGIN"
steamcmd +login "$LOGIN" +run_app_build "$(pwd)/steam/app_build.vdf" +quit
