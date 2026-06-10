#!/bin/sh
# Universal NetBird Updater (Armbian & Alpine)
# Targets: MXQ, Orange Pi, Raspberry Pi, etc.
# Handles: Architecture detection, SSL issues, and Redirects.

set -e

INSTALL_DIR="/usr/bin"
echo "--- NetBird Update Manager ---"

# 1. Root Check
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Please run as root (sudo)"
    exit 1
fi

# 2. Architecture Detection (Works for both Armbian and Alpine)
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    aarch64|arm64) BIN_ARCH="arm64" ;;
    armv7*|armhf)  BIN_ARCH="armv7" ;;
    x86_64|amd64)  BIN_ARCH="amd64" ;;
    *) echo "Error: Unsupported architecture $ARCH_RAW"; exit 1 ;;
esac

# 3. Check for curl
if ! command -v curl >/dev/null; then
    echo "Installing curl..."
    if command -v apk >/dev/null; then apk add curl; else apt-get update && apt-get install -y curl; fi
fi

# 4. Get Latest Version from GitHub
echo "[1/4] Checking for updates..."
# -skI: follow redirect headers, ignore SSL certificate/date errors
LATEST_TAG=$(curl -skI https://github.com/netbirdio/netbird/releases/latest | grep -i "location:" | awk -F/ '{print $NF}' | tr -d '\r')

if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" = "latest" ]; then
    # Fallback if headers fail
    LATEST_TAG=$(curl -sk https://github.com/netbirdio/netbird/releases/latest | grep -o 'tag/v[0-9.]*' | head -n 1 | cut -d/ -f2 | tr -d '\r')
fi

LATEST_VER=$(echo "$LATEST_TAG" | sed 's/^v//')

# 5. Version Comparison
if command -v netbird >/dev/null; then
    CURRENT_VER=$(netbird version | awk '{print $1}' | tr -d '\r')
    echo "      Detected Architecture: $BIN_ARCH"
    echo "      Currently installed:   $CURRENT_VER"
    echo "      Latest available:      $LATEST_VER"

    if [ "$CURRENT_VER" = "$LATEST_VER" ]; then
        echo "------------------------------------------------"
        echo "Result: NetBird is already up to date. Skipping."
        exit 0
    fi
    echo "      Status: New version found!"
else
    echo "      Architecture: $BIN_ARCH"
    echo "      Status: NetBird not installed. Proceeding with fresh install."
fi

# 6. Download Section
FILENAME="netbird_${LATEST_VER}_linux_${BIN_ARCH}.tar.gz"
URL="https://github.com/netbirdio/netbird/releases/download/${LATEST_TAG}/${FILENAME}"

echo "[2/4] Downloading: $FILENAME"
cd /tmp
# -Lk: L follows redirect to download server, k ignores clock/SSL errors
if ! curl -Lk --progress-bar -o netbird_update.tar.gz "$URL"; then
    echo "Error: Download failed. Check network."
    exit 1
fi

# 7. Update Binary
echo "[3/4] Extracting and updating binary..."
tar -xzf netbird_update.tar.gz netbird

# Stop service if it's running (to release file lock)
if command -v netbird >/dev/null; then
    netbird service stop 2>/dev/null || true
fi

mv -f netbird $INSTALL_DIR/netbird
chmod +x $INSTALL_DIR/netbird
rm -f netbird_update.tar.gz

# 8. Restart Service
echo "[4/4] Restarting NetBird service..."
# Netbird's 'service' command works on both Armbian (Systemd) and Alpine (OpenRC)
netbird service install 2>/dev/null || true
netbird service start 2>/dev/null || true

echo "------------------------------------------------"
echo "Success! NetBird is now version: $(netbird version)"