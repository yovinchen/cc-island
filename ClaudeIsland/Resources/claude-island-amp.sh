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
  echo "claude-island-amp: amp CLI not found" >&2
  exit 127
fi

exec env PLUGINS=all "$AMP_BIN" "$@"
