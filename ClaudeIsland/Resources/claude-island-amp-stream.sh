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
ERROR_FILE="$(mktemp -t claude-island-amp-stream.error.XXXXXX)"
STDERR_FILE="$(mktemp -t claude-island-amp-stream.stderr.XXXXXX)"
STREAM_FILE="$(mktemp -t claude-island-amp-stream.jsonl.XXXXXX)"

cleanup() {
  rm -f "$LAST_FILE" "$ERROR_FILE" "$STDERR_FILE" "$STREAM_FILE"
}

trap cleanup EXIT

send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"
send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"

PARSER='import json, pathlib, re, subprocess, sys
last_path = pathlib.Path(sys.argv[1])
error_path = pathlib.Path(sys.argv[2])
stream_path = pathlib.Path(sys.argv[3])
bridge = sys.argv[4]
session_id = sys.argv[5]
cwd = sys.argv[6]
last_text = ""
result_error = ""
tool_calls = {}
seen_pre = set()
seen_post = set()
ansi_re = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")

def send(payload):
    if not bridge:
        return
    try:
        subprocess.run([bridge, "--source", "amp_cli"], input=json.dumps(payload).encode(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    except Exception:
        pass

def stringify_content(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, dict):
                if item.get("type") == "text" and item.get("text"):
                    parts.append(item["text"])
                else:
                    parts.append(json.dumps(item, ensure_ascii=False))
            else:
                parts.append(str(item))
        return "\\n".join(part for part in parts if part)
    if value is None:
        return ""
    return json.dumps(value, ensure_ascii=False)

for raw in stream_path.read_text().splitlines():
    raw = ansi_re.sub("", raw).strip()
    if not raw:
        continue
    try:
        obj = json.loads(raw)
    except Exception:
        continue
    msg_type = obj.get("type")
    message = obj.get("message") or {}
    content = message.get("content") or []
    if msg_type == "assistant":
        texts = [item.get("text") for item in content if isinstance(item, dict) and item.get("type") == "text" and item.get("text")]
        if texts:
            last_text = "\\n".join(texts)
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") != "tool_use":
                continue
            tool_id = item.get("id") or item.get("tool_use_id")
            if not tool_id:
                continue
            tool_calls[tool_id] = {
                "name": item.get("name"),
                "input": item.get("input"),
            }
            if tool_id in seen_pre:
                continue
            seen_pre.add(tool_id)
            send({
                "hook_event_name": "PreToolUse",
                "session_id": session_id,
                "cwd": cwd,
                "tool_name": item.get("name"),
                "tool_input": item.get("input"),
                "tool_use_id": tool_id,
            })
    elif msg_type == "user":
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") != "tool_result":
                continue
            tool_id = item.get("tool_use_id")
            if not tool_id or tool_id in seen_post:
                continue
            seen_post.add(tool_id)
            metadata = tool_calls.get(tool_id, {})
            is_error = bool(item.get("is_error"))
            send({
                "hook_event_name": "PostToolUseFailure" if is_error else "PostToolUse",
                "session_id": session_id,
                "cwd": cwd,
                "tool_name": metadata.get("name"),
                "tool_input": metadata.get("input"),
                "tool_use_id": tool_id,
                "tool_response": stringify_content(item.get("content")),
                "error": stringify_content(item.get("content")) if is_error else None,
            })
    elif msg_type == "result":
        if obj.get("is_error"):
            result_error = stringify_content(obj.get("error") or obj.get("message") or obj.get("subtype"))
        elif isinstance(obj.get("result"), str) and obj.get("result").strip():
            last_text = obj["result"].strip()
        elif isinstance(obj.get("message"), str) and obj.get("message").strip():
            last_text = obj["message"].strip()

last_path.write_text(last_text)
error_path.write_text(result_error)'

if [ "$AMP_BIN" = "$AMP_WRAPPER" ]; then
  "$AMP_BIN" --execute "$PROMPT" --stream-json 2>"$STDERR_FILE" | tee "$STREAM_FILE"
else
  env PLUGINS=all "$AMP_BIN" --execute "$PROMPT" --stream-json 2>"$STDERR_FILE" | tee "$STREAM_FILE"
fi
STATUS=$?

BRIDGE_PATH=""
if [ -x "$BRIDGE" ]; then
  BRIDGE_PATH="$BRIDGE"
fi
python3 -c "$PARSER" "$LAST_FILE" "$ERROR_FILE" "$STREAM_FILE" "$BRIDGE_PATH" "$SESSION_ID" "$PWD"

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
    send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Amp stream-json finished\"}"
  fi
elif [ -n "$RESULT_ERROR" ]; then
  notify_error "$RESULT_ERROR"
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Amp stream-json reported an execution error\"}"
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
