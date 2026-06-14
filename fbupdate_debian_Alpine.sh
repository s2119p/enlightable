#!/bin/sh
set -e

REPO="filebrowser/filebrowser"
BIN_PATH="/usr/local/bin/filebrowser"
TMP_DIR="/tmp/tmp_update"
RETRY_CLEAN_TMP="/tmp/*"
MAX_RETRIES=1

# Dependency check
for cmd in curl jq tar; do
    if ! command -v $cmd > /dev/null 2>&1; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

# Detect service manager
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

# Current version
if [ -f "$BIN_PATH" ]; then
    if VERSION_OUT=$($BIN_PATH version 2>&1); then
        CURRENT_VERSION=$(echo "$VERSION_OUT" | awk '{print $NF}' | sed 's/^v//;s/\/.*//')
    else
        CURRENT_VERSION="corrupted"
    fi
else
    CURRENT_VERSION="none"
fi

# Get latest version from GitHub API
LATEST_TAG=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name' 2>/dev/null || echo "")
LATEST_VERSION=$(echo "$LATEST_TAG" | sed 's/^v//')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" = "null" ]; then
    echo "Error: Could not fetch the latest version from GitHub API."
    exit 1
fi

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "Already up to date."
    exit 0
fi

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    SEARCH_TERM="linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    SEARCH_TERM="linux-arm64"
else
    echo "Error: Unsupported architecture $ARCH"
    exit 1
fi

LATEST_URL=$(curl -sL "https://api.github.com/repos/$REPO/releases/latest" \
    | jq -r '.assets[] | select(.name | contains("'$SEARCH_TERM'")) | .browser_download_url' | head -n1)

if [ -z "$LATEST_URL" ] || [ "$LATEST_URL" = "null" ]; then
    echo "Error: Could not find a download asset for $SEARCH_TERM."
    exit 1
fi

# Stop service before changes
if [ "$SERVICE_MGR" = "systemd" ]; then
    systemctl stop $SERVICE_NAME || true
else
    rc-service $SERVICE_NAME stop || true
fi

# Remove old binary (only the binary file)
if [ -f "$BIN_PATH" ]; then
    rm -f "$BIN_PATH" || true
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

download_and_extract() {
    set +e
    curl -L -o "$TMP_DIR/fb.tar.gz" "$LATEST_URL"
    CURL_EXIT=$?
    set -e
    if [ $CURL_EXIT -ne 0 ]; then
        return 1
    fi

    set +e
    tar -xzf "$TMP_DIR/fb.tar.gz" -C "$TMP_DIR"
    TAR_EXIT=$?
    set -e
    if [ $TAR_EXIT -ne 0 ]; then
        return 2
    fi

    EXTRACTED_BIN=$(find "$TMP_DIR" -type f -name "filebrowser" | head -n1)
    if [ -z "$EXTRACTED_BIN" ]; then
        return 3
    fi

    return 0
}

attempt=0
while :; do
    attempt=$((attempt+1))
    if download_and_extract; then
        break
    else
        if [ $attempt -le $MAX_RETRIES ]; then
            rm -f "$BIN_PATH" || true
            rm -rf $RETRY_CLEAN_TMP || true
            rm -rf "$TMP_DIR"
            mkdir -p "$TMP_DIR"
            continue
        else
            echo "Download/extract failed after retries. Service remains stopped."
            exit 1
        fi
    fi
done

chmod +x "$EXTRACTED_BIN"
mv "$EXTRACTED_BIN" "$BIN_PATH"

if [ "$SERVICE_MGR" = "systemd" ]; then
    systemctl start $SERVICE_NAME
else
    rc-service $SERVICE_NAME start || true
fi

rm -rf "$TMP_DIR"
$BIN_PATH version
