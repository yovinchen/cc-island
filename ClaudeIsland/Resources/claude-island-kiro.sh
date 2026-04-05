#!/bin/zsh

KIRO_BIN=""
for CANDIDATE in "$HOME/.local/bin/kiro-cli" "/opt/homebrew/bin/kiro-cli" "/usr/local/bin/kiro-cli" "$HOME/.local/bin/kiro" "/opt/homebrew/bin/kiro" "/usr/local/bin/kiro" "kiro-cli" "kiro"; do
  if [ "$CANDIDATE" = "kiro-cli" ] || [ "$CANDIDATE" = "kiro" ]; then
    if command -v "$CANDIDATE" >/dev/null 2>&1; then
      KIRO_BIN="$(command -v "$CANDIDATE")"
      break
    fi
  elif [ -x "$CANDIDATE" ]; then
    KIRO_BIN="$CANDIDATE"
    break
  fi
done

if [ -z "$KIRO_BIN" ]; then
  echo "claude-island-kiro: Kiro CLI not found" >&2
  exit 127
fi

exec "$KIRO_BIN" --agent claude-island "$@"
