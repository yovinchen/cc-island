#!/bin/zsh

PI_BIN=""
BRIDGE="$HOME/.claude-island/bin/claude-island-bridge-launcher.sh"

if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="pi-$(uuidgen)"
else
  SESSION_ID="pi-$(date +%s)-$$"
fi

escape_json() {
  python3 - <<'PY' "$1"
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

send_event() {
  local payload="$1"
  if [ -x "$BRIDGE" ]; then
    print -rn -- "$payload" | "$BRIDGE" --source pi >/dev/null 2>&1 || true
  fi
}

notify_error() {
  local message="$1"
  local cwd_json
  local msg_json
  cwd_json="$(escape_json "$PWD")"
  msg_json="$(escape_json "$message")"
  send_event "{\"hook_event_name\":\"Notification\",\"session_id\":\"$SESSION_ID\",\"cwd\":$cwd_json,\"message\":$msg_json,\"notification_type\":\"error\"}"
}

for CANDIDATE in "$HOME/.local/bin/pi" "/opt/homebrew/bin/pi" "/usr/local/bin/pi" "pi"; do
  if [ "$CANDIDATE" = "pi" ]; then
    if command -v pi >/dev/null 2>&1; then
      PI_BIN="$(command -v pi)"
      break
    fi
  elif [ -x "$CANDIDATE" ]; then
    PI_BIN="$CANDIDATE"
    break
  fi
done

if [ -z "$PI_BIN" ]; then
  notify_error "Pi Coding Agent not found for claude-island-pi"
  echo "claude-island-pi: Pi Coding Agent not found" >&2
  exit 127
fi

CWD_JSON="$(escape_json "$PWD")"
send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"

if [ "$#" -gt 0 ]; then
  PROMPT="$*"
  PROMPT_JSON="$(escape_json "$PROMPT")"
  send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"
fi

"$PI_BIN" "$@"
STATUS=$?

if [ $STATUS -eq 0 ]; then
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Pi exited\"}"
else
  notify_error "Pi exited with code $STATUS"
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Pi exited with code $STATUS\"}"
fi

exit $STATUS
