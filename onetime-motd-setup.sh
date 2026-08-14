#!/bin/sh

# 1. Determine if elevated privileges are needed
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas >/dev/null 2>&1; then
        SUDO="doas"
    fi
fi

# 2. Clear static MOTD
$SUDO sh -c '> /etc/motd' 2>/dev/null || true

# 3. Download the initial copy of unified-motd.sh IMMEDIATELY
RAW_URL="https://raw.githubusercontent.com/s2119p/enlightable/main/unified-motd.sh"
LOCAL_CACHE="/var/tmp/github_motd.sh"

if command -v curl >/dev/null 2>&1; then
    $SUDO curl -sSL "$RAW_URL" -o "$LOCAL_CACHE"
elif command -v wget >/dev/null 2>&1; then
    $SUDO wget -q "$RAW_URL" -O "$LOCAL_CACHE"
fi
$SUDO chmod +x "$LOCAL_CACHE" 2>/dev/null || true

# 4. Create the auto-sync launcher script
$SUDO sh -c 'cat << "EOF" > /etc/profile.d/99-motd.sh
#!/bin/sh

# Prevent duplicate execution in the same shell session
if [ -n "$MOTD_SHOWN" ]; then
    return 0 2>/dev/null || exit 0
fi
export MOTD_SHOWN=1

RAW_URL="https://raw.githubusercontent.com/s2119p/enlightable/main/unified-motd.sh"
LOCAL_CACHE="/var/tmp/github_motd.sh"

# 1. Execute local cached version immediately if available
if [ -f "$LOCAL_CACHE" ]; then
    . "$LOCAL_CACHE"
fi

# 2. Fetch latest version from GitHub in background
(
    (
        if command -v curl >/dev/null 2>&1; then
            curl -s --max-time 3 "$RAW_URL" -o "${LOCAL_CACHE}.tmp"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -T 3 "$RAW_URL" -O "${LOCAL_CACHE}.tmp"
        fi

        if [ -s "${LOCAL_CACHE}.tmp" ]; then
            mv "${LOCAL_CACHE}.tmp" "$LOCAL_CACHE"
            chmod +x "$LOCAL_CACHE"
        else
            rm -f "${LOCAL_CACHE}.tmp"
        fi
    ) >/dev/null 2>&1 &
)
EOF'

# 5. Make executable
$SUDO chmod +x /etc/profile.d/99-motd.sh

# 6. Ensure non-login desktop terminals (Tuxedo, Ubuntu, Debian GUI) also load the MOTD
if [ -f "$HOME/.bashrc" ]; then
    if ! grep -q "99-motd.sh" "$HOME/.bashrc"; then
        echo '[ -f /etc/profile.d/99-motd.sh ] && . /etc/profile.d/99-motd.sh' >> "$HOME/.bashrc"
    fi
fi

if [ -f "$HOME/.zshrc" ]; then
    if ! grep -q "99-motd.sh" "$HOME/.zshrc"; then
        echo '[ -f /etc/profile.d/99-motd.sh ] && . /etc/profile.d/99-motd.sh' >> "$HOME/.zshrc"
    fi
fi
