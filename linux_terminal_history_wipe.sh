rm -f ~/.ash_history ~/.bash_history ~/.zsh_history 2>/dev/null
export HISTFILE=/dev/null
set +o history 2>/dev/null || true
history -c 2>/dev/null || true
printf "\033[0;32m[✓] History wiped and recording disabled.\033[0m\n"
