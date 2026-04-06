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

ARGS=("$@")

for ARG in "${ARGS[@]}"; do
  case "$ARG" in
    --help|-h|help|version|--version)
      exec "$KIRO_BIN" "$@"
      ;;
    --agent=*|-a=*)
      exec "$KIRO_BIN" "$@"
      ;;
  esac
done

INDEX=1
while [ $INDEX -le $# ]; do
  CURRENT="${ARGS[$INDEX-1]}"
  if [ "$CURRENT" = "--agent" ] || [ "$CURRENT" = "-a" ]; then
    exec "$KIRO_BIN" "$@"
  fi
  INDEX=$((INDEX + 1))
done

export CLAUDE_ISLAND_KIRO_WRAPPER=1

exec "$KIRO_BIN" --agent claude-island "$@"
