#!/bin/zsh

set -o pipefail

AMP_BIN=""
BRIDGE="$HOME/.claude-island/bin/claude-island-bridge-launcher.sh"
AMP_WRAPPER="$HOME/.claude-island/bin/claude-island-amp"

if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="amp-stream-$(uuidgen)"
else
  SESSION_ID="amp-stream-$(date +%s)-$$"
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
    print -rn -- "$payload" | "$BRIDGE" --source amp_cli >/dev/null 2>&1 || true
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

if [ -x "$AMP_WRAPPER" ]; then
  AMP_BIN="$AMP_WRAPPER"
else
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
fi

if [ -z "$AMP_BIN" ]; then
  notify_error "Amp CLI not found for claude-island-amp-stream"
  echo "claude-island-amp-stream: amp CLI not found" >&2
  exit 127
fi

if [ "$#" -gt 0 ]; then
  PROMPT="$*"
else
  PROMPT="$(cat)"
fi

if [ -z "$PROMPT" ]; then
  notify_error "Prompt required for claude-island-amp-stream"
  echo "claude-island-amp-stream: prompt required" >&2
  exit 1
fi

PROMPT_JSON="$(escape_json "$PROMPT")"
CWD_JSON="$(escape_json "$PWD")"
LAST_FILE="$(mktemp -t claude-island-amp-stream.last.XXXXXX)"
STDERR_FILE="$(mktemp -t claude-island-amp-stream.stderr.XXXXXX)"

cleanup() {
  rm -f "$LAST_FILE" "$STDERR_FILE"
}

trap cleanup EXIT

send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"
send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"

PARSER='import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
last_text = ""
for raw in sys.stdin:
    sys.stdout.write(raw)
    sys.stdout.flush()
    try:
        obj = json.loads(raw)
    except Exception:
        continue
    if obj.get("type") != "assistant":
        continue
    content = (obj.get("message") or {}).get("content") or []
    texts = [item.get("text") for item in content if isinstance(item, dict) and item.get("type") == "text" and item.get("text")]
    if texts:
        last_text = "\\n".join(texts)
path.write_text(last_text)'

if [ "$AMP_BIN" = "$AMP_WRAPPER" ]; then
  "$AMP_BIN" --execute --stream-json "$PROMPT" 2>"$STDERR_FILE" | python3 -c "$PARSER" "$LAST_FILE"
else
  env PLUGINS=all "$AMP_BIN" --execute --stream-json "$PROMPT" 2>"$STDERR_FILE" | python3 -c "$PARSER" "$LAST_FILE"
fi
STATUS=$?

LAST_ASSISTANT_MESSAGE=""
if [ -f "$LAST_FILE" ]; then
  LAST_ASSISTANT_MESSAGE="$(cat "$LAST_FILE")"
fi

if [ $STATUS -eq 0 ]; then
  if [ -n "$LAST_ASSISTANT_MESSAGE" ]; then
    LAST_JSON="$(escape_json "$LAST_ASSISTANT_MESSAGE")"
    send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"last_assistant_message\":$LAST_JSON}"
  else
    send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Amp stream-json finished\"}"
  fi
else
  ERROR_OUTPUT="$(cat "$STDERR_FILE")"
  if [ -n "$ERROR_OUTPUT" ]; then
    notify_error "$ERROR_OUTPUT"
  else
    notify_error "Amp stream-json failed with exit code $STATUS"
  fi
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Amp stream-json failed\"}"
fi

if [ -s "$STDERR_FILE" ]; then
  cat "$STDERR_FILE" >&2
fi

exit $STATUS
