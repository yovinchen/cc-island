#!/bin/zsh

set -o pipefail

COPILOT_BIN=""
BRIDGE="$HOME/.claude-island/bin/claude-island-bridge-launcher.sh"

if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="copilot-json-$(uuidgen)"
else
  SESSION_ID="copilot-json-$(date +%s)-$$"
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
    print -rn -- "$payload" | "$BRIDGE" --source copilot >/dev/null 2>&1 || true
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

for CANDIDATE in "$HOME/.nvm/versions/node/v22.20.0/bin/copilot" "$HOME/.local/bin/copilot" "/opt/homebrew/bin/copilot" "/usr/local/bin/copilot" "copilot"; do
  if [ "$CANDIDATE" = "copilot" ]; then
    if command -v copilot >/dev/null 2>&1; then
      COPILOT_BIN="$(command -v copilot)"
      break
    fi
  elif [ -x "$CANDIDATE" ]; then
    COPILOT_BIN="$CANDIDATE"
    break
  fi
done

if [ -z "$COPILOT_BIN" ]; then
  notify_error "Copilot CLI not found for claude-island-copilot-json"
  echo "claude-island-copilot-json: Copilot CLI not found" >&2
  exit 127
fi

if [ "$#" -gt 0 ]; then
  PROMPT="$*"
else
  PROMPT="$(cat)"
fi

if [ -z "$PROMPT" ]; then
  notify_error "Prompt required for claude-island-copilot-json"
  echo "claude-island-copilot-json: prompt required" >&2
  exit 1
fi

PROMPT_JSON="$(escape_json "$PROMPT")"
CWD_JSON="$(escape_json "$PWD")"
LAST_FILE="$(mktemp -t claude-island-copilot-json.last.XXXXXX)"
ERROR_FILE="$(mktemp -t claude-island-copilot-json.error.XXXXXX)"
STDERR_FILE="$(mktemp -t claude-island-copilot-json.stderr.XXXXXX)"
STREAM_FILE="$(mktemp -t claude-island-copilot-json.stream.XXXXXX)"

cleanup() {
  rm -f "$LAST_FILE" "$ERROR_FILE" "$STDERR_FILE" "$STREAM_FILE"
}

trap cleanup EXIT

send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"
send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"

PARSER='import json, pathlib, sys
last_path = pathlib.Path(sys.argv[1])
error_path = pathlib.Path(sys.argv[2])
stream_path = pathlib.Path(sys.argv[3])
stderr_path = pathlib.Path(sys.argv[4])
last_text = ""
result_error = ""

def remember_text(value):
    global last_text
    if isinstance(value, str) and value.strip():
        last_text = value.strip()

def remember_error(value):
    global result_error
    if isinstance(value, str) and value.strip():
        result_error = value.strip()

for raw in stream_path.read_text().splitlines():
    raw = raw.strip()
    if not raw:
        continue
    try:
        obj = json.loads(raw)
    except Exception:
        continue

    if not isinstance(obj, dict):
        continue

    event_type = obj.get("type")
    data = obj.get("data") if isinstance(obj.get("data"), dict) else {}

    if event_type == "assistant.message":
        remember_text(data.get("content"))
    elif event_type == "result":
        if obj.get("exitCode") not in (0, None):
            remember_error(data.get("message") or obj.get("message") or "Copilot JSON mode failed")
        usage = obj.get("usage")
        if isinstance(usage, dict):
            code_changes = usage.get("codeChanges")
            if isinstance(code_changes, dict):
                files = code_changes.get("filesModified")
                if isinstance(files, list) and files:
                    remember_text("\\n".join(str(item) for item in files))

stderr_text = stderr_path.read_text().strip()
if stderr_text:
    remember_error(stderr_text)

last_path.write_text(last_text)
error_path.write_text(result_error)'

"$COPILOT_BIN" -p "$PROMPT" --output-format json --allow-all-tools --allow-all-paths --allow-all-urls --no-ask-user >"$STREAM_FILE" 2>"$STDERR_FILE"
STATUS=$?

python3 -c "$PARSER" "$LAST_FILE" "$ERROR_FILE" "$STREAM_FILE" "$STDERR_FILE"

LAST_ASSISTANT_MESSAGE=""
if [ -f "$LAST_FILE" ]; then
  LAST_ASSISTANT_MESSAGE="$(cat "$LAST_FILE")"
fi

RESULT_ERROR=""
if [ -f "$ERROR_FILE" ]; then
  RESULT_ERROR="$(cat "$ERROR_FILE")"
fi

if [ $STATUS -eq 0 ] && [ -z "$RESULT_ERROR" ]; then
  if [ -n "$LAST_ASSISTANT_MESSAGE" ]; then
    LAST_JSON="$(escape_json "$LAST_ASSISTANT_MESSAGE")"
    send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"last_assistant_message\":$LAST_JSON}"
  else
    send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Copilot JSON mode finished\"}"
  fi
else
  if [ -n "$RESULT_ERROR" ]; then
    notify_error "$RESULT_ERROR"
  else
    notify_error "Copilot JSON mode failed with exit code $STATUS"
  fi
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Copilot JSON mode failed\"}"
fi

if [ -s "$STREAM_FILE" ]; then
  cat "$STREAM_FILE"
fi

if [ -s "$STDERR_FILE" ]; then
  cat "$STDERR_FILE" >&2
fi

exit $STATUS
