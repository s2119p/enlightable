#!/bin/sh
# ==============================================================================
# Master One-Time MOTD Installer for Alpine, Debian, Ubuntu, Tuxedo OS, Proxmox
# ==============================================================================

MOTD_LAUNCHER="/etc/profile.d/99-motd.sh"
LOCAL_CACHE="/var/tmp/github_motd.sh"
RAW_URL="https://raw.githubusercontent.com/s2119p/enlightable/main/unified-motd.sh"

# 1. Clear static MOTD
> /etc/motd 2>/dev/null || true

# 2. Download initial copy of unified-motd.sh immediately
if command -v curl >/dev/null 2>&1; then
    curl -sSL "$RAW_URL" -o "$LOCAL_CACHE"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$RAW_URL" -O "$LOCAL_CACHE"
fi
chmod 755 "$LOCAL_CACHE" 2>/dev/null || true

# 3. Create the auto-sync launcher script with PID ($$) Guard
cat << "EOF" > "$MOTD_LAUNCHER"
#!/bin/sh

# Prevent duplicate execution in the same shell process ($$)
if [ "$MOTD_SHOWN" = "$$" ]; then
    return 0 2>/dev/null || exit 0
fi
MOTD_SHOWN="$$"

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
            chmod 755 "$LOCAL_CACHE"
        else
            rm -f "${LOCAL_CACHE}.tmp"
        fi
    ) >/dev/null 2>&1 &
)
EOF

chmod 755 "$MOTD_LAUNCHER"

# 4. Helper function to configure .bashrc / .zshrc
add_to_rc() {
    rc_file="$1"
    if [ -f "$rc_file" ]; then
        if ! grep -q "99-motd.sh" "$rc_file"; then
            echo '[ -f /etc/profile.d/99-motd.sh ] && . /etc/profile.d/99-motd.sh' >> "$rc_file"
        fi
    fi
}

# Configure current user and root
add_to_rc "$HOME/.bashrc"
add_to_rc "$HOME/.zshrc"

# Configure sudo user's home directory if applicable
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
    add_to_rc "$USER_HOME/.bashrc"
    add_to_rc "$USER_HOME/.zshrc"
fi
