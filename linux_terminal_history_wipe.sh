#!/bin/sh

# 1. Stop history tracking and set size to 0
export HISTFILE=/dev/null
export HISTSIZE=0

# 2. Only run 'history -c' on Bash/Zsh (avoids the 1200-line print bug in Alpine ash)
if [ -n "$BASH_VERSION" ] || [ -n "$ZSH_VERSION" ]; then
    set +o history 2>/dev/null || true
    history -c 2>/dev/null || true
fi

# 3. Delete all history files on disk
rm -f "$HOME/.ash_history" "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.history" 2>/dev/null || true

printf "\033[0;32m[✓] History wiped. Resetting active shell...\033[0m\n"

# 4. Replace current shell with a clean session to instantly purge RAM history
# (Does NOT disconnect your SSH session or LXC container)
CURRENT_SHELL="$(which "${SHELL##*/}" 2>/dev/null || which sh 2>/dev/null || echo /bin/sh)"
exec "$CURRENT_SHELL"
