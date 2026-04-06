#!/bin/zsh

CRUSH_BIN=""
BRIDGE="$HOME/.claude-island/bin/claude-island-bridge-launcher.sh"

if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="crush-$(uuidgen)"
else
  SESSION_ID="crush-$(date +%s)-$$"
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
    print -rn -- "$payload" | "$BRIDGE" --source crush >/dev/null 2>&1 || true
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

for CANDIDATE in "$HOME/.local/bin/crush" "/opt/homebrew/bin/crush" "/usr/local/bin/crush" "crush"; do
  if [ "$CANDIDATE" = "crush" ]; then
    if command -v crush >/dev/null 2>&1; then
      CRUSH_BIN="$(command -v crush)"
      break
    fi
  elif [ -x "$CANDIDATE" ]; then
    CRUSH_BIN="$CANDIDATE"
    break
  fi
done

if [ -z "$CRUSH_BIN" ]; then
  notify_error "Crush CLI not found for claude-island-crush"
  echo "claude-island-crush: Crush CLI not found" >&2
  exit 127
fi

CWD_JSON="$(escape_json "$PWD")"
send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"

if [ "$#" -gt 0 ]; then
  PROMPT="$*"
  PROMPT_JSON="$(escape_json "$PROMPT")"
  send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"
fi

"$CRUSH_BIN" "$@"
STATUS=$?

if [ $STATUS -eq 0 ]; then
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Crush exited\"}"
else
  notify_error "Crush exited with code $STATUS"
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Crush exited with code $STATUS\"}"
fi

exit $STATUS
