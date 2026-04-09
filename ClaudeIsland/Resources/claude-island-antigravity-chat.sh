#!/bin/zsh

set -o pipefail

ANTIGRAVITY_BIN=""
BRIDGE="$HOME/.claude-island/bin/claude-island-bridge-launcher.sh"

if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="antigravity-chat-$(uuidgen)"
else
  SESSION_ID="antigravity-chat-$(date +%s)-$$"
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
    print -rn -- "$payload" | "$BRIDGE" --source antigravity >/dev/null 2>&1 || true
  fi
}

notify_error() {
  local message="$1"
  local cwd_json msg_json
  cwd_json="$(escape_json "$PWD")"
  msg_json="$(escape_json "$message")"
  send_event "{\"hook_event_name\":\"Notification\",\"session_id\":\"$SESSION_ID\",\"cwd\":$cwd_json,\"message\":$msg_json,\"notification_type\":\"error\"}"
}

for CANDIDATE in "$HOME/.antigravity/antigravity/bin/antigravity" "/Applications/Antigravity.app/Contents/MacOS/Antigravity" "antigravity"; do
  if [ "$CANDIDATE" = "antigravity" ]; then
    if command -v antigravity >/dev/null 2>&1; then
      ANTIGRAVITY_BIN="$(command -v antigravity)"
      break
    fi
  elif [ -x "$CANDIDATE" ]; then
    ANTIGRAVITY_BIN="$CANDIDATE"
    break
  fi
done

if [ -z "$ANTIGRAVITY_BIN" ]; then
  notify_error "Antigravity CLI not found for claude-island-antigravity-chat"
  echo "claude-island-antigravity-chat: antigravity not found" >&2
  exit 127
fi

if [ "$#" -gt 0 ]; then
  PROMPT="$*"
else
  PROMPT="$(cat)"
fi

if [ -z "$PROMPT" ]; then
  notify_error "Prompt required for claude-island-antigravity-chat"
  echo "claude-island-antigravity-chat: prompt required" >&2
  exit 1
fi

PROMPT_JSON="$(escape_json "$PROMPT")"
CWD_JSON="$(escape_json "$PWD")"
STDERR_FILE="$(mktemp -t claude-island-antigravity.stderr.XXXXXX)"

cleanup() {
  rm -f "$STDERR_FILE"
}
trap cleanup EXIT

send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"
send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"

"$ANTIGRAVITY_BIN" chat "$PROMPT" > /dev/null 2>"$STDERR_FILE"
STATUS=$?

SANITIZED_STDERR="$(python3 - <<'PY' "$STDERR_FILE"
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(errors='ignore') if path.exists() else ''
lines = []
for line in text.splitlines():
    stripped = line.strip()
    if not stripped:
        continue
    if "SecCodeCheckValidity" in stripped:
        continue
    lines.append(stripped)
print("\n".join(lines), end="")
PY
)"

if [ $STATUS -eq 0 ]; then
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Antigravity chat launched\"}"
else
  if [ -n "$SANITIZED_STDERR" ]; then
    notify_error "$SANITIZED_STDERR"
    print -r -- "$SANITIZED_STDERR" >&2
  else
    notify_error "Antigravity chat failed with exit code $STATUS"
    print -r -- "Antigravity chat failed with exit code $STATUS" >&2
  fi
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Antigravity chat failed\"}"
fi

exit $STATUS
