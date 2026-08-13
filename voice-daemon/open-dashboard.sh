#!/bin/bash
# Launch the Jarvis dashboard: start the read-only local data endpoint if it
# isn't already up, then open it as a Chrome app-mode window (no tabs/toolbar
# — the Mac-app feel from the design brief).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8765
VENV_PY="$HOME/.hermes/hermes-agent/venv/bin/python"

if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/api/snapshot"; then
  nohup "$VENV_PY" "$DIR/dashboard_server.py" "$PORT" \
    > "$DIR/dashboard-server.log" 2>&1 &
  sleep 1
fi

open -na "Google Chrome" --args \
  --app="http://127.0.0.1:$PORT/" \
  --window-size=1400,900
