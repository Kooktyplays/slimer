#!/bin/bash
# Export Slimer for every configured platform.
#
#   ./tools/build.sh            all platforms
#   ./tools/build.sh macos      just one (macos | windows | linux | web)
#
# Output goes to ../build/<platform>/. The macOS app is also zipped, because
# a .app is a directory and loses its executable bits over most transports.

set -u
GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.." || exit 1
OUT="../build"
TARGET="${1:-all}"
FAILED=0

if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT (override with GODOT=/path/to/Godot)"
  exit 1
fi

# Opening the project in the Godot editor rewrites export_presets.cfg and can
# rename a preset to its platform name ("Windows" -> "Windows Desktop"), which
# silently breaks a hardcoded name. Resolve the real name from the file, and
# say so loudly if it is missing entirely.
resolve_preset() {
  local wanted="$1"
  if grep -q "^name=\"$wanted\"$" export_presets.cfg; then
    echo "$wanted"
    return 0
  fi
  local alt
  alt=$(grep "^name=\"" export_presets.cfg | sed 's/name="\(.*\)"/\1/' \
        | grep -i "^$wanted" | head -1)
  [ -n "$alt" ] && echo "$alt"
}

# Embedding an icon into a .exe needs rcedit, a Windows tool that needs Wine on
# macOS. Leaving the option on without it makes every build warn and embed
# nothing. The Godot editor rewrites export_presets.cfg whenever it feels like
# it and keeps flipping this back on, so the build enforces it here rather than
# trusting a file another program owns. See STEAM.md to turn it on for real.
enforce_windows_resources() {
  local rcedit_ok=1
  command -v wine >/dev/null 2>&1 || rcedit_ok=0
  [ -f "$HOME/rcedit.exe" ] || rcedit_ok=0

  local want="false"
  [ "$rcedit_ok" -eq 1 ] && want="true"

  if grep -q "^application/modify_resources=$want$" export_presets.cfg; then
    return
  fi
  python3 - "$want" <<'PY'
import pathlib, re, sys
want = sys.argv[1]
p = pathlib.Path("export_presets.cfg")
s = p.read_text()
start = s.index('name="Windows"')
nxt = s.find("[preset.", s.index("[preset.", start) + 8)
nxt = len(s) if nxt == -1 else nxt
block = re.sub(r'^application/modify_resources=.*$',
               'application/modify_resources=' + want, s[start:nxt], flags=re.M)
p.write_text(s[:start] + block + s[nxt:])
PY
  echo "    (set application/modify_resources=$want)"
}

run_export() {
  local wanted="$1" path="$2" label="$3"
  local preset
  preset=$(resolve_preset "$wanted")
  if [ -z "$preset" ]; then
    echo "==> $label"
    echo "    FAILED: no export preset named '$wanted' in export_presets.cfg"
    FAILED=1
    return
  fi
  mkdir -p "$(dirname "$path")"
  echo "==> $label"

  local log
  log=$("$GODOT" --headless --path . --export-release "$preset" "$path" 2>&1 \
        | sed 's/\x1b\[[0-9;]*m//g')

  # Report warnings too. An earlier version only grepped for ^ERROR, so an
  # export that warned about a missing rcedit and quietly shipped a
  # default-icon .exe was reported as "ok" - a build script that hides
  # problems is worse than no build script.
  local errors warnings
  errors=$(echo "$log" | grep -E "^ERROR|Project export .* failed")
  warnings=$(echo "$log" | grep -E "^WARNING" | grep -v "completed with warnings")

  if [ -n "$errors" ]; then
    echo "$errors" | sed 's/^/    /'
    echo "    FAILED: $label"
    FAILED=1
    return
  fi
  if [ ! -e "$path" ]; then
    echo "    FAILED: $label produced no output at $path"
    FAILED=1
    return
  fi
  if [ -n "$warnings" ]; then
    echo "$warnings" | sort -u | sed 's/^/    warning: /'
    echo "    ok (with warnings): $path"
  else
    echo "    ok: $path"
  fi
}

[ "$TARGET" = "all" ] || [ "$TARGET" = "macos" ] && {
  rm -rf "$OUT/macos/Slimer.app"
  run_export "macOS" "$OUT/macos/Slimer.app" "macOS (universal, ad-hoc signed)"
  if [ -d "$OUT/macos/Slimer.app" ]; then
    # Godot's "ad-hoc signed" export only leaves the linker's signature on the
    # Mach-O: no _CodeSignature, no sealed resources. The code directory still
    # claims resources must be sealed, so verification fails and macOS reports
    # the app as "damaged and can't be opened" - which, unlike the unsigned
    # warning, right-click -> Open will NOT get past. Sign it here for real.
    #
    # arm64 makes this mandatory rather than cosmetic: Apple Silicon refuses to
    # execute a binary whose signature does not validate.
    codesign --force --deep --sign - --timestamp=none "$OUT/macos/Slimer.app" 2>&1 \
      | sed 's/^/    /'
    if codesign --verify --deep --strict "$OUT/macos/Slimer.app" 2>/dev/null; then
      echo "    signed: ad-hoc, sealed resources verified"
    else
      echo "    ERROR: macOS signature does not verify - the app will be"
      echo "           reported as damaged. Not shipping this build."
      FAILED=1
    fi

    # ditto, not zip: it preserves the bundle's symlinks, permissions and the
    # signature. A plain zip breaks all three.
    ( cd "$OUT/macos" && rm -f Slimer-macos.zip \
      && ditto -c -k --sequesterRsrc --keepParent Slimer.app Slimer-macos.zip )
    echo "    zipped: $OUT/macos/Slimer-macos.zip"

    # The build is still not notarised, so a *downloaded* copy carries a
    # quarantine flag that Gatekeeper honours regardless of the signature.
    # Users clear it with:  xattr -dr com.apple.quarantine /path/to/Slimer.app
  fi
}

[ "$TARGET" = "all" ] || [ "$TARGET" = "windows" ] && {
  enforce_windows_resources
  run_export "Windows" "$OUT/windows/Slimer.exe" "Windows (x86_64)"
}

[ "$TARGET" = "all" ] || [ "$TARGET" = "linux" ] && \
  run_export "Linux" "$OUT/linux/Slimer.x86_64" "Linux (x86_64)"

[ "$TARGET" = "all" ] || [ "$TARGET" = "web" ] && {
  # wipe first: the editor has changed this preset's export_path before, which
  # left a whole second build sitting alongside the current one
  rm -rf "$OUT/web"
  run_export "Web" "$OUT/web/index.html" "Web (HTML5)"
}

echo
echo "build sizes:"
du -sh "$OUT"/* 2>/dev/null

exit $FAILED
