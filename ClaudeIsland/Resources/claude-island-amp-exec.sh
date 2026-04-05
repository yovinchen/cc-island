#!/bin/zsh

AMP_BIN=""
for CANDIDATE in "$HOME/.local/bin/amp" "/opt/homebrew/bin/amp" "/usr/local/bin/amp" "amp"; do
  if [ "$CANDIDATE" = "amp" ]; then
    if command -v amp >/dev/null 2>&1; then
      AMP_BIN="$(command -v amp)"
      break
    fi
  elif [ -x "$CANDIDATE" ]; then
    AMP_BIN="$CANDIDATE"
    break
  fi
done

if [ -z "$AMP_BIN" ]; then
  echo "claude-island-amp-exec: amp CLI not found" >&2
  exit 127
fi

BRIDGE="$HOME/.claude-island/bin/claude-island-bridge-launcher.sh"

if [ "$#" -gt 0 ]; then
  PROMPT="$*"
else
  PROMPT="$(cat)"
fi

if [ -z "$PROMPT" ]; then
  echo "claude-island-amp-exec: prompt required" >&2
  exit 1
fi

if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="amp-exec-$(uuidgen)"
else
  SESSION_ID="amp-exec-$(date +%s)-$$"
fi

send_event() {
  local payload="$1"
  if [ -x "$BRIDGE" ]; then
    print -rn -- "$payload" | "$BRIDGE" --source amp_cli >/dev/null 2>&1 || true
  fi
}

escape_json() {
  python3 - <<'PY' "$1"
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

PROMPT_JSON="$(escape_json "$PROMPT")"
CWD_JSON="$(escape_json "$PWD")"

send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"
send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"

RESULT="$(env PLUGINS=all "$AMP_BIN" --execute "$PROMPT" 2>&1)"
STATUS=$?

RESULT_JSON="$(escape_json "$RESULT")"

if [ $STATUS -eq 0 ]; then
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"last_assistant_message\":$RESULT_JSON}"
else
  send_event "{\"hook_event_name\":\"Notification\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":$RESULT_JSON,\"notification_type\":\"error\"}"
fi

print -r -- "$RESULT"
exit $STATUS
