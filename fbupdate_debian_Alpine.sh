#!/bin/sh
set -e

# ============================
# Configuration
# ============================
REPO="filebrowser/filebrowser"
BIN_PATH="/usr/local/bin/filebrowser"
TMP_DIR="/tmp/tmp_update"

echo "--- Starting Filebrowser Update Check ---"

# 1. Dependency Check
for cmd in curl jq tar; do
    if ! command -v $cmd > /dev/null 2>&1; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

# 2. Detect Service Manager
if command -v systemctl > /dev/null 2>&1; then
    SERVICE_MGR="systemd"
    SERVICE_NAME="filebrowser"
elif command -v rc-service > /dev/null 2>&1; then
    SERVICE_MGR="openrc"
    SERVICE_NAME="filebrowser"
else
    echo "Error: No supported service manager found."
    exit 1
fi

# 3. Universal Version Check
if [ -f "$BIN_PATH" ]; then
    echo "Checking current version..."
    if VERSION_OUT=$($BIN_PATH version 2>&1); then
        CURRENT_VERSION=$(echo "$VERSION_OUT" | awk '{print $NF}' | sed 's/^v//;s/\/.*//')
    else
        echo "Warning: Existing binary crashed or is corrupted."
        CURRENT_VERSION="corrupted"
    fi
    echo "Current Version: $CURRENT_VERSION"
else
    CURRENT_VERSION="none"
    echo "Filebrowser is not currently installed."
fi

# Get latest version from GitHub API
LATEST_TAG=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name' 2>/dev/null || echo "")
LATEST_VERSION=$(echo $LATEST_TAG | sed 's/^v//')

# --- NEW FAIL-SAFE CHECK ---
if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    echo "Error: Could not fetch the latest version from GitHub API."
    echo "Check your internet connection or GitHub API rate limits."
    exit 1
fi
# ---------------------------

echo "Latest Version:  $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "--- You are already up to date. No action needed. ---"
    exit 0
fi

# 4. Detect Architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    SEARCH_TERM="linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    SEARCH_TERM="linux-arm64"
else
    echo "Error: Unsupported architecture $ARCH"
    exit 1
fi

echo "Updating to $LATEST_VERSION ($SEARCH_TERM)..."

# 5. Download and Extract
LATEST_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
    | jq -r '.assets[] | select(.name | contains("'$SEARCH_TERM'")) | .browser_download_url' | head -n1)

mkdir -p "$TMP_DIR"
curl -L -o "$TMP_DIR/fb.tar.gz" "$LATEST_URL"
tar -xzf "$TMP_DIR/fb.tar.gz" -C "$TMP_DIR"
EXTRACTED_BIN=$(find "$TMP_DIR" -type f -name "filebrowser")

# 6. Stop Service
echo "Stopping service via $SERVICE_MGR..."
if [ "$SERVICE_MGR" = "systemd" ]; then
    systemctl stop $SERVICE_NAME || true
else
    rc-service $SERVICE_NAME stop || true
fi

# 7. Install Binary
chmod +x "$EXTRACTED_BIN"
mv "$EXTRACTED_BIN" "$BIN_PATH"

# 8. Start Service
echo "Restarting service..."
if [ "$SERVICE_MGR" = "systemd" ]; then
    systemctl start $SERVICE_NAME
else
    rc-service $SERVICE_NAME start
fi

rm -rf "$TMP_DIR"
echo "--- Update Successful! ---"
$BIN_PATH version
