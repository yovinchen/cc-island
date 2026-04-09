#!/bin/zsh

AMP_BIN=""
BRIDGE="$HOME/.claude-island/bin/claude-island-bridge-launcher.sh"
AMP_WRAPPER="$HOME/.claude-island/bin/claude-island-amp"

if command -v uuidgen >/dev/null 2>&1; then
  SESSION_ID="amp-exec-$(uuidgen)"
else
  SESSION_ID="amp-exec-$(date +%s)-$$"
fi

escape_json() {
  python3 - <<'PY' "$1"
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

debug_log() {
  if [ "${CLAUDE_ISLAND_DEBUG:-}" = "1" ]; then
    print -r -- "$1" >&2
  fi
}

send_event() {
  local payload="$1"
  if [ -x "$BRIDGE" ]; then
    if ! print -rn -- "$payload" | "$BRIDGE" --source amp_cli >/dev/null 2>&1; then
      debug_log "claude-island-amp-exec: failed to deliver event to bridge"
    fi
  else
    debug_log "claude-island-amp-exec: bridge launcher not found at $BRIDGE"
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
  notify_error "Amp CLI not found for claude-island-amp-exec"
  echo "claude-island-amp-exec: amp CLI not found" >&2
  exit 127
fi

if [ "$#" -gt 0 ]; then
  PROMPT="$*"
else
  PROMPT="$(cat)"
fi

if [ -z "$PROMPT" ]; then
  notify_error "Prompt required for claude-island-amp-exec"
  echo "claude-island-amp-exec: prompt required" >&2
  exit 1
fi

PROMPT_JSON="$(escape_json "$PROMPT")"
CWD_JSON="$(escape_json "$PWD")"

send_event "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON}"
send_event "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"prompt\":$PROMPT_JSON}"

STDOUT_FILE="$(mktemp -t claude-island-amp-exec.stdout.XXXXXX)"
STDERR_FILE="$(mktemp -t claude-island-amp-exec.stderr.XXXXXX)"

cleanup() {
  rm -f "$STDOUT_FILE" "$STDERR_FILE"
}

trap cleanup EXIT

if [ "$AMP_BIN" = "$AMP_WRAPPER" ]; then
  "$AMP_BIN" --execute "$PROMPT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
else
  env PLUGINS=all "$AMP_BIN" --execute "$PROMPT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
fi
STATUS=$?

RESULT="$(cat "$STDOUT_FILE")"
ERROR_OUTPUT="$(cat "$STDERR_FILE")"
SANITIZED_ERROR_OUTPUT="$(python3 - <<'PY' "$STDERR_FILE"
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text(errors="ignore") if path.exists() else ""
text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text).strip()
print(text, end="")
PY
)"

RESULT_JSON="$(escape_json "$RESULT")"

if [ $STATUS -eq 0 ]; then
  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"last_assistant_message\":$RESULT_JSON}"
else
  if [ -n "$SANITIZED_ERROR_OUTPUT" ]; then
    if [[ "$SANITIZED_ERROR_OUTPUT" == *"Cannot reach Amp servers"* ]]; then
      notify_error "Amp CLI cannot reach Amp servers from the current environment."
    else
      notify_error "$SANITIZED_ERROR_OUTPUT"
    fi
  elif [ -n "$RESULT" ]; then
    notify_error "$RESULT"
  else
    notify_error "Amp execute failed with exit code $STATUS"
  fi

  send_event "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SESSION_ID\",\"cwd\":$CWD_JSON,\"message\":\"Amp execute failed\"}"
fi

if [ -n "$RESULT" ]; then
  print -r -- "$RESULT"
fi

if [ -n "$SANITIZED_ERROR_OUTPUT" ]; then
  print -r -- "$SANITIZED_ERROR_OUTPUT" >&2
fi

exit $STATUS
