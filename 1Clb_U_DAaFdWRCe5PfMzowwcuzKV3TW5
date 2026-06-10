#!/bin/sh
set -euo pipefail

REPO="traefik/traefik"
BIN_DIR="/usr/bin"
BIN="$BIN_DIR/traefik"
TMP_DIR="/mnt/lnvoBkp/impo/traefik"
RETRIES=3
CURL_OPTS="--fail --silent --show-error --location --max-time 30"

echo "--- Starting Traefik Update Check ---"

if command -v systemctl > /dev/null 2>&1; then
    SERVICE_MGR="systemd"
    SERVICE_NAME="traefik"
elif command -v rc-service > /dev/null 2>&1; then
    SERVICE_MGR="openrc"
    SERVICE_NAME="traefik"
else
    echo "Error: No supported service manager found."
    exit 1
fi

# Determine current version
if [ -x "$BIN" ]; then
    CURRENT_VERSION=$("$BIN" version 2>/dev/null | awk '/Version:/ {print $2; exit}')
    if [ -z "$CURRENT_VERSION" ]; then
        echo "Warning: could not parse version"
        CURRENT_VERSION="unknown"
    fi
    echo "Current Version: $CURRENT_VERSION"
else
    CURRENT_VERSION="none"
    echo "traefik is not currently installed."
fi

# Fetch latest release metadata
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

# Compare before downloading
if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "Current Version is the same as released version, skipping download."
    exit 0
fi


mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"/tmp_extract* "$TMP_DIR"/asset_* "$TMP_DIR"/release.json 2>/dev/null || true' EXIT

i=0
LATEST_TAG=""
while [ $i -lt $RETRIES ] && [ -z "$LATEST_TAG" ]; do
    curl $CURL_OPTS "https://api.github.com/repos/$REPO/releases/latest" -o "$TMP_DIR/release.json" || true
    LATEST_TAG=$(jq -r '.tag_name // empty' "$TMP_DIR/release.json" 2>/dev/null || true)
    if [ -n "$LATEST_TAG" ]; then
        break
    fi
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
    x86_64) SEARCH_TERM="linux_amd64" ;;
    aarch64|arm64) SEARCH_TERM="linux_arm64" ;;
    *) echo "Error: Unsupported architecture $ARCH"; exit 1 ;;
esac
echo "Updating to $LATEST_VERSION ($SEARCH_TERM)..."

i=0
ASSET_URL=""
while [ $i -lt $RETRIES ] && [ -z "$ASSET_URL" ]; do
    ASSET_URL=$(jq -r --arg term "$SEARCH_TERM" '.assets[] | select((.name|ascii_downcase) | test($term)) | .browser_download_url' "$TMP_DIR/release.json" 2>/dev/null | head -n1 || true)
    if [ -n "$ASSET_URL" ]; then
        break
    fi
    i=$((i+1))
    sleep 1
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

if file "$ASSET_PATH" | grep -qiE 'gzip|tar archive|compress|zip'; then
    EXTRACT_DIR="$TMP_DIR/tmp_extract_$$"
    mkdir -p "$EXTRACT_DIR"
    case "$(file -b --mime-type "$ASSET_PATH")" in
        application/zip) unzip -q "$ASSET_PATH" -d "$EXTRACT_DIR" ;;
        application/gzip|application/x-gzip|application/x-tar) tar -xzf "$ASSET_PATH" -C "$EXTRACT_DIR" ;;
        *) tar -xzf "$ASSET_PATH" -C "$EXTRACT_DIR" || true ;;
    esac
    EXTRACTED_BIN=$(find "$EXTRACT_DIR" -type f -name "traefik" -perm /111 | head -n1 || true)
else
    EXTRACTED_BIN="$ASSET_PATH"
    chmod +x "$EXTRACTED_BIN"
fi

if [ -z "$EXTRACTED_BIN" ] || [ ! -f "$EXTRACTED_BIN" ]; then
    echo "Error: Could not locate extracted traefik binary."
    exit 1
fi

echo "Stopping service via $SERVICE_MGR..."
if [ "$SERVICE_MGR" = "systemd" ]; then
    systemctl stop "$SERVICE_NAME" || true
else
    rc-service "$SERVICE_NAME" stop || true
fi

echo "Installing binary to $BIN ..."
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
