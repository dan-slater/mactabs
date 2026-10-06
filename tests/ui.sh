#!/bin/bash
# UI harness: launches build/Tabs.app against a throwaway library, drives it through the
# TABS_TEST_FIFO hook (the same code path the voice commands use) and through real
# keystrokes (System Events), reads state back as JSON and screenshots the window.
#
#   tests/ui.sh            run everything
#   KEEP=1 tests/ui.sh     leave the app open at the end
#
# Needs: build/Tabs.app (make), python3 for JSON, and — for the keystroke leg only —
# Accessibility permission for the terminal (the leg is skipped with a warning otherwise).
set -u
cd "$(dirname "$0")/.."
APP=build/Tabs.app/Contents/MacOS/Tabs
WORK=$(mktemp -d /tmp/tabs-ui.XXXXXX)
LIB=$WORK/Tabs; FIFO=$WORK/cmd; OUT=$FIFO.out; SHOTS=${SHOTS:-tests/shots}
mkdir -p "$LIB" "$SHOTS"; mkfifo "$FIFO"
cp "tests/fixtures/sample.tab" "$LIB/Pink Floyd - Wish You Were Here.tab"
cp "tests/fixtures/second.tab" "$LIB/Second - Tab.tab"
pass=0; fail=0
ok()   { echo "  ✓ $1"; pass=$((pass+1)); }
bad()  { echo "  ✗ $1"; fail=$((fail+1)); }
say()  { echo "$1" >&3; }
shot() { # real screenshot of the window (needs Screen Recording for the terminal; falls back to the in-app render)
  local w; w=$(state | field window)
  screencapture -x -o -l "$w" "$PWD/$SHOTS/$1.png" 2>/dev/null && [ -s "$PWD/$SHOTS/$1.png" ] || say "shot $PWD/$SHOTS/$1.png"
  sleep 0.3
}
state(){ : > "$OUT"; say state; sleep 0.3; cat "$OUT"; }
field(){ python3 -c "import json,sys; print(json.loads(sys.stdin.readline())['$1'])"; }
check(){ # check <label> <python expr over s=state dict>
  local s; s=$(state)
  if python3 -c "import json,sys; s=json.loads(sys.stdin.readline()); sys.exit(0 if ($2) else 1)" <<<"$s"; then ok "$1"; else bad "$1  ← $s"; fi
}

pkill -x Tabs 2>/dev/null; sleep 0.3
TABS_DIR="$LIB" TABS_TEST_FIFO="$FIFO" "$APP" >"$WORK/app.log" 2>&1 &
PID=$!
trap '[ -n "${KEEP:-}" ] || kill $PID 2>/dev/null; echo "work dir: $WORK"' EXIT
exec 3>"$FIFO"   # one writer for the whole run: lines stream in order
sleep 2.5
kill -0 $PID 2>/dev/null || { echo "app died:"; cat "$WORK/app.log"; exit 1; }

echo "== load"
check "first tab opened"              "s['tab']=='Wish You Were Here'"
check "speed read from frontmatter"   "abs(s['speed']-0.6)<1e-6"
check "not running at start"          "s['running']==False and s['y']<1"
check "no tab line wraps"             "s['fragments']==s['lines']"
shot 01-loaded

echo "== voice path (same code the recogniser calls)"
say go; sleep 2
check "'go' starts scrolling"         "s['running']==True and s['y']>5"
y1=$(state | field y)
say faster; say faster; say faster; sleep 0.3
check "'faster' x3 compounds 1.15^3"  "abs(s['speed']-0.6*1.15**3)<1e-3"
sleep 2
check "scrolling continues faster"    "s['y']>$y1+20"
shot 02-scrolling
say stop; sleep 0.3
check "'stop' pauses"                 "s['running']==False"
y2=$(state | field y); sleep 1
check "paused really holds position"  "abs(s['y']-$y2)<1"
say slower; sleep 1.8   # > the 1.5s debounce → speed persisted to the file
check "'slower' then persists to file" "abs(s['fileScroll']-s['speed'])<1e-2 and abs(s['speed']-0.6*1.15**2)<1e-3"
grep -q "^scroll: 0.79" "$LIB/Pink Floyd - Wish You Were Here.tab" && ok "frontmatter rewritten (scroll: 0.79)" || { bad "frontmatter not rewritten"; head -9 "$LIB/Pink Floyd - Wish You Were Here.tab"; }
grep -q "^\[Outro\]" "$LIB/Pink Floyd - Wish You Were Here.tab" && ok "body intact after rewrite" || bad "body lost on rewrite"
say top; sleep 0.6
check "'top' returns to the start"    "s['y']<1"

echo "== keyboard (System Events)"
if osascript -e 'tell application "System Events" to tell process "Tabs" to set frontmost to true' \
             -e 'tell application "System Events" to key code 49' 2>"$WORK/osa.err"; then
  sleep 0.5
  check "space toggles scrolling"     "s['running']==True"
  v0=$(state | field speed)
  osascript -e 'tell application "System Events" to key code 126' -e 'tell application "System Events" to key code 126'; sleep 0.3
  check "↑ ↑ speeds up by 1.15^2"     "abs(s['speed']/$v0-1.15**2)<1e-3"
  osascript -e 'tell application "System Events" to keystroke "c"'; sleep 0.4
  check "c hides chord panel"         "s['chords']==False"
  shot 03-no-chords
  osascript -e 'tell application "System Events" to keystroke "c"'; sleep 0.3
  osascript -e 'tell application "System Events" to key code 49'; sleep 0.3
  check "space pauses again"          "s['running']==False"
  osascript -e 'tell application "System Events" to keystroke "]"'; sleep 0.5
  check "] jumps to a later section"  "s['y']>30"
  shot 04-section
  osascript -e 'tell application "System Events" to keystroke "t"'; sleep 0.5
  check "t returns to top"            "s['y']<1"
  osascript -e 'tell application "System Events" to key code 125' -e 'tell application "System Events" to key code 125'; sleep 0.3
  check "↓ ↓ back to where it was"    "abs(s['speed']-$v0)<1e-3"
else
  echo "  ! keystroke leg skipped — grant Accessibility to the terminal: $(cat "$WORK/osa.err")"
fi

echo "== library watch"
cat > "$LIB/Third - Added Live.tab" <<'EOF'
---
title: Added Live
artist: Third
---
[Verse]
G D Em C
some words
EOF
sleep 1
ls "$LIB" | grep -q "Third" && ok "file dropped into the folder" || bad "fixture write failed"
sleep 0.5
echo "  (sidebar refresh is visual — see 05-library.png)"
shot 05-library

echo
echo "passed $pass, failed $fail — shots in $SHOTS/"
[ $fail -eq 0 ]
