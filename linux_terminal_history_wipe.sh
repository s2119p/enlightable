#!/bin/sh

# 1. Unset and redirect history file to /dev/null
export HISTFILE=/dev/null
unset HISTSIZE

# 2. Disable history if the shell supports it (bash/zsh)
set +o history 2>/dev/null || true

# 3. Wipe physical history files for ash, bash, and zsh
rm -f "$HOME/.ash_history" "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.history" 2>/dev/null || true

# 4. Clear in-memory buffer if supported
history -c 2>/dev/null || true

printf "\033[0;32m[✓] Alpine history wiped successfully.\033[0m\n"
