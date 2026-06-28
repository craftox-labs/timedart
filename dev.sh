#!/usr/bin/env bash
set -euo pipefail
FIFO=/tmp/tt_flutter_cmd     # fixed path so a second shell can find it
rm -f "$FIFO"; mkfifo "$FIFO"

# keep a writer open so flutter never sees EOF and quits
sleep infinity > "$FIFO" &
SLEEP_PID=$!

cleanup() { kill "$SLEEP_PID" "$FLUTTER_PID" 2>/dev/null || true; rm -f "$FIFO"; }
trap cleanup EXIT INT TERM

flutter run -d linux < "$FIFO" &
FLUTTER_PID=$!

# debounce so saving mid-keystroke doesn't reload on broken code
watchexec -w lib -e dart --debounce 500ms -- "printf r > '$FIFO'"


# printf r > /tmp/tt_flutter_cmd   # hot reload
# printf R > /tmp/tt_flutter_cmd   # hot restart
# printf p > /tmp/tt_flutter_cmd   # toggle debug paint (widget wireframes)
# printf q > /tmp/tt_flutter_cmd   # quit
