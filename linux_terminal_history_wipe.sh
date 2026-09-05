#!/bin/sh

# 1. Turn off history recording for the active session
set +o history 2>/dev/null || true

# 2. Redirect HISTFILE to /dev/null so no buffer writes on exit
export HISTFILE=/dev/null

# 3. Wipe standard history files (covers ash, bash, zsh)
rm -f "$HOME/.ash_history" "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.history"

# 4. Clear active in-memory history buffer
history -c 2>/dev/null || true

printf "\033[0;32m[✓] Terminal history wiped and recording disabled.\033[0m\n"
