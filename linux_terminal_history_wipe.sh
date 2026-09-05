set +o history 2>/dev/null || true
export HISTFILE=/dev/null
rm -f ~/.ash_history ~/.bash_history ~/.zsh_history ~/.history 2>/dev/null || true
history -c 2>/dev/null || true
printf "\033[0;32m[✓] History wiped and recording disabled.\033[0m\n"
