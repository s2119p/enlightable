#!/bin/sh
set -euo pipefail

REPO="cloudflare/cloudflared"
BIN_DIR="/usr/bin"
BIN="$BIN_DIR/cloudflared"
TMP_DIR="/mnt/lnvoBkp/impo/cloudflared"
RETRIES=3
CURL_OPTS="--fail --silent --show-error --location --max-time 30"

echo "--- Starting Cloudflared Update Check ---"

if command -v systemctl > /dev/null 2>&1; then
    SERVICE_MGR="systemd"
    SERVICE_NAME="cloudflared"
elif command -v rc-service > /dev/null 2>&1; then
    SERVICE_MGR="openrc"
    SERVICE_NAME="cloudflared"
else
    echo "Error: No supported service manager found."
    exit 1
fi

if [ -x "$BIN" ]; then
    VERSION_OUT=$("$BIN" version 2>/dev/null || true)
    CURRENT_VERSION=$(printf '%s\n' "$VERSION_OUT" | sed -n 's/.*version[[:space:]]\?\([0-9]\+\(\.[0-9]\+\)*\).*/\1/p' || true)
    if [ -z "$CURRENT_VERSION" ]; then
        echo "Warning: could not parse version; raw output:"
        echo "$VERSION_OUT"
        CURRENT_VERSION="corrupted"
    fi
    echo "Current Version: $CURRENT_VERSION"
else
    CURRENT_VERSION="none"
    echo "cloudflared is not currently installed."
fi

mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"/tmp_extract* "$TMP_DIR"/asset_* "$TMP_DIR"/release.json 2>/dev/null || true' EXIT

i=0
LATEST_TAG=""
while [ $i -lt $RETRIES ] && [ -z "$LATEST_TAG" ]; do
    curl $CURL_OPTS "https://api.github.com/repos/$REPO/releases/latest" -o "$TMP_DIR/release.json" || true
    LATEST_TAG=$(jq -r '.tag_name // empty' "$TMP_DIR/release.json" 2>/dev/null || true)
    [ -n "$LATEST_TAG" ] && break
    i=$((i+1))
    sleep 1
done

if [ -z "$LATEST_TAG" ]; then
    echo "Error: Could not fetch the latest version from GitHub API."
    exit 1
fi

LATEST_VERSION=$(echo "$LATEST_TAG" | sed 's/^v//')
echo "Latest Version: $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "Current Version is the same as released version, do not need to update."
    exit 0
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64) SEARCH_TERM="linux-amd64" ;;
    aarch64|arm64) SEARCH_TERM="linux-arm64" ;;
    *) echo "Error: Unsupported architecture $ARCH"; exit 1 ;;
esac
echo "Updating to $LATEST_VERSION ($SEARCH_TERM)..."

i=0
ASSET_URL=""
while [ $i -lt $RETRIES ] && [ -z "$ASSET_URL" ]; do
    ASSET_URL=$(jq -r --arg term "$SEARCH_TERM" '.assets[] | select((.name|ascii_downcase) | test($term)) | .browser_download_url' "$TMP_DIR/release.json" 2>/dev/null | head -n1 || true)
    i=$((i+1))
    [ -n "$ASSET_URL" ] || sleep 1
done

echo "Resolved ASSET_URL: '$ASSET_URL'"
if [ -z "$ASSET_URL" ]; then
    echo "Error: Could not find a release asset matching '$SEARCH_TERM'."
    echo "Available assets (name -> url):"
    jq -r '.assets[] | "\(.name) -> \(.browser_download_url)"' "$TMP_DIR/release.json" || true
    exit 1
fi

ASSET_PATH="$TMP_DIR/asset_$$"
curl $CURL_OPTS -o "$ASSET_PATH" "$ASSET_URL"

# Avoid using 'file' command by checking the URL extension
case "$ASSET_URL" in
    *.tar.gz|*.tgz)
        EXTRACT_DIR="$TMP_DIR/tmp_extract_$$"
        mkdir -p "$EXTRACT_DIR"
        tar -xzf "$ASSET_PATH" -C "$EXTRACT_DIR"
        EXTRACTED_BIN=$(find "$EXTRACT_DIR" -type f -name "cloudflared" | head -n1 || true)
        ;;
    *)
        EXTRACTED_BIN="$ASSET_PATH"
        chmod +x "$EXTRACTED_BIN"
        ;;
esac

if [ -z "$EXTRACTED_BIN" ] || [ ! -f "$EXTRACTED_BIN" ]; then
    echo "Error: Could not locate extracted cloudflared binary."
    exit 1
fi

echo "Stopping service via $SERVICE_MGR..."
if [ "$SERVICE_MGR" = "systemd" ]; then
    systemctl stop "$SERVICE_NAME" || true
else
    rc-service "$SERVICE_NAME" stop || true
fi

# Wait up to 5 seconds for the service to exit gracefully
echo "Ensuring service is stopped..."
for j in 1 2 3 4 5; do
    PID=$(pidof cloudflared || true)
    if [ -z "$PID" ]; then
        break
    fi
    sleep 1
done

# Force-kill if it is still running to free system resources and locked disk sectors
PID=$(pidof cloudflared || true)
if [ -n "$PID" ]; then
    echo "Service refused to stop gracefully. Force-killing process(es): $PID"
    kill -9 $PID || true
    sleep 1
fi

echo "Installing binary to $BIN ..."
# Explicitly remove the old binary to immediately release its disk space on the rootfs
if [ -f "$BIN" ]; then
    rm -f "$BIN"
fi

chmod +x "$EXTRACTED_BIN"
mv -f "$EXTRACTED_BIN" "$BIN"
chown root:root "$BIN"
chmod 0755 "$BIN"

echo "Restarting service..."
if [ "$SERVICE_MGR" = "systemd" ]; then
    systemctl start "$SERVICE_NAME"
else
    rc-service "$SERVICE_NAME" start || true
fi

echo "--- Update Successful! ---"
"$BIN" version