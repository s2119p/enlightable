#!/bin/sh
# ==============================================================================
# Master One-Time MOTD Installer (Auto-installs chafa on all distros)
# ==============================================================================

MOTD_LAUNCHER="/etc/profile.d/99-motd.sh"
LOCAL_CACHE="/var/tmp/github_motd.sh"
FLAG_CACHE="/var/tmp/np-flag.png"
RAW_URL="https://raw.githubusercontent.com/s2119p/enlightable/main/my/unified-motd.sh"
FLAG_URL="https://raw.githubusercontent.com/s2119p/enlightable/main/my/np-flag.png"

# 1. Clear static MOTD
> /etc/motd 2>/dev/null || true

# 2. Auto-Detect Package Manager & Install chafa
install_chafa() {
    if ! command -v chafa >/dev/null 2>&1; then
        echo "--> chafa not found. Installing chafa automatically..."
        if command -v apk >/dev/null 2>&1; then
            # Alpine Linux
            apk add chafa >/dev/null 2>&1 || true
        elif command -v apt-get >/dev/null 2>&1; then
            # Debian / Ubuntu / Mint / Tuxedo OS / Proxmox
            apt-get update -qq >/dev/null 2>&1 || true
            apt-get install -y -qq chafa >/dev/null 2>&1 || true
        elif command -v dnf >/dev/null 2>&1; then
            # Fedora / RHEL / Rocky / AlmaLinux
            dnf install -y -q chafa >/dev/null 2>&1 || true
        elif command -v pacman >/dev/null 2>&1; then
            # Arch Linux / Manjaro
            pacman -Sy --noconfirm chafa >/dev/null 2>&1 || true
        elif command -v zypper >/dev/null 2>&1; then
            # openSUSE
            zypper -n in chafa >/dev/null 2>&1 || true
        fi
    fi
}
install_chafa

# 3. Download unified-motd.sh & np-flag.png immediately
if command -v curl >/dev/null 2>&1; then
    curl -sSLf "$RAW_URL" -o "$LOCAL_CACHE"
    curl -sSLf "$FLAG_URL" -o "$FLAG_CACHE"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$RAW_URL" -O "$LOCAL_CACHE"
    wget -q "$FLAG_URL" -O "$FLAG_CACHE"
fi
chmod 755 "$LOCAL_CACHE" 2>/dev/null || true
chmod 644 "$FLAG_CACHE" 2>/dev/null || true

# 4. Create the auto-sync launcher script with PID ($$) Guard
cat << "EOF" > "$MOTD_LAUNCHER"
#!/bin/sh

# Prevent duplicate execution in the same shell process ($$)
if [ "$MOTD_SHOWN" = "$$" ]; then
    return 0 2>/dev/null || exit 0
fi
MOTD_SHOWN="$$"

RAW_URL="https://raw.githubusercontent.com/s2119p/enlightable/main/my/unified-motd.sh"
FLAG_URL="https://raw.githubusercontent.com/s2119p/enlightable/main/my/np-flag.png"
LOCAL_CACHE="/var/tmp/github_motd.sh"
FLAG_CACHE="/var/tmp/np-flag.png"

# 1. Execute local cached version immediately if available
if [ -f "$LOCAL_CACHE" ]; then
    . "$LOCAL_CACHE"
fi

# 2. Fetch latest version from GitHub in background
(
    (
        if command -v curl >/dev/null 2>&1; then
            curl -sSLf --max-time 3 "$RAW_URL" -o "${LOCAL_CACHE}.tmp"
            [ ! -f "$FLAG_CACHE" ] && curl -sSLf --max-time 3 "$FLAG_URL" -o "$FLAG_CACHE"
        elif command -v wget >/dev/null 2>&1; then
            wget -q -T 3 "$RAW_URL" -O "${LOCAL_CACHE}.tmp"
            [ ! -f "$FLAG_CACHE" ] && wget -q -T 3 "$FLAG_URL" -O "$FLAG_CACHE"
        fi

        if [ -s "${LOCAL_CACHE}.tmp" ] && ! grep -q "404: Not Found" "${LOCAL_CACHE}.tmp"; then
            mv "${LOCAL_CACHE}.tmp" "$LOCAL_CACHE"
            chmod 755 "$LOCAL_CACHE"
        else
            rm -f "${LOCAL_CACHE}.tmp"
        fi
    ) >/dev/null 2>&1 &
)
EOF

chmod 755 "$MOTD_LAUNCHER"

# 5. Configure .bashrc / .zshrc for non-login desktop terminals
add_to_rc() {
    rc_file="$1"
    if [ -f "$rc_file" ]; then
        if ! grep -q "99-motd.sh" "$rc_file"; then
            echo '[ -f /etc/profile.d/99-motd.sh ] && . /etc/profile.d/99-motd.sh' >> "$rc_file"
        fi
    fi
}

add_to_rc "$HOME/.bashrc"
add_to_rc "$HOME/.zshrc"

if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
    add_to_rc "$USER_HOME/.bashrc"
    add_to_rc "$USER_HOME/.zshrc"
fi
