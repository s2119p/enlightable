#!/bin/sh
set -euo pipefail

REPO="cloudflare/cloudflared"
BIN_DIR="/usr/bin"
BIN="$BIN_DIR/cloudflared"
TMP_DIR="/mnt/lnvoBkp/impo/cloudflared"
RETRIES=3

echo "--- Starting Cloudflared Update Check ---"

# 1. Dependency Validation
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required tool '$cmd' is not installed."
    echo "Please run: apk update && apk add $cmd ca-certificates"
    exit 1
  fi
done

# 2. Identify Service Manager
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

# 3. Check Current Version
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
CURL_ERR_LOG="$TMP_DIR/curl_error_$$"
trap 'rm -rf "$TMP_DIR"/tmp_extract* "$TMP_DIR"/asset_* "$TMP_DIR"/release.json "$CURL_ERR_LOG" 2>/dev/null || true' EXIT

# 4. Fetch Release Info
i=0
LATEST_TAG=""

while [ $i -lt $RETRIES ] && [ -z "$LATEST_TAG" ]; do
  if curl --fail --show-error --location --max-time 30 \
    -H "User-Agent: cloudflared-updater" \
    -H "Accept: application/vnd.github.v3+json" \
    -o "$TMP_DIR/release.json" \
    "https://api.github.com/repos/$REPO/releases/latest" 2>"$CURL_ERR_LOG"; then
    
    LATEST_TAG=$(jq -r '.tag_name' "$TMP_DIR/release.json" 2>/dev/null || true)
    if [ "$LATEST_TAG" = "null" ]; then
      LATEST_TAG=""
    fi
  else
    echo "Attempt $((i+1)) to fetch release metadata failed."
    if [ -f "$CURL_ERR_LOG" ]; then
      cat "$CURL_ERR_LOG"
    fi
  fi

  [ -n "$LATEST_TAG" ] && break

  i=$((i+1))
  sleep 1
done

if [ -z "$LATEST_TAG" ]; then
  echo "Error: Could not fetch the latest version from GitHub."
  exit 1
fi

LATEST_VERSION="$LATEST_TAG"

# 5. Version Comparison
CLEAN_CURRENT=$(printf '%s\n' "$CURRENT_VERSION" | sed 's/^v//')
CLEAN_LATEST=$(printf '%s\n' "$LATEST_VERSION" | sed 's/^v//')

if [ "$CLEAN_CURRENT" = "$CLEAN_LATEST" ]; then
  echo "cloudflared is already up to date ($CURRENT_VERSION)."
  exit 0
fi

# 6. Determine Architecture & Target Exact Bare Binary Asset
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) SEARCH_TERM="cloudflared-linux-amd64" ;;
  aarch64|arm64) SEARCH_TERM="cloudflared-linux-arm64" ;;
  *) echo "Error: Unsupported architecture $ARCH"; exit 1 ;;
esac

echo "Updating to $LATEST_VERSION ($SEARCH_TERM)..."

# 7. Resolve Download URL (Exact Match Selection)
i=0
ASSET_URL=""
while [ $i -lt $RETRIES ] && [ -z "$ASSET_URL" ]; do
  ASSET_URL=$(jq -r --arg term "$SEARCH_TERM" '.assets[] | select(.name == $term) | .browser_download_url' "$TMP_DIR/release.json" 2>/dev/null || true)
  i=$((i+1))
  [ -n "$ASSET_URL" ] || sleep 1
done

echo "Resolved ASSET_URL: '$ASSET_URL'"

if [ -z "$ASSET_URL" ]; then
  echo "Error: Could not find a release asset matching exactly '$SEARCH_TERM'."
  echo "Available assets (name -> url):"
  jq -r '.assets[] | "\(.name) -> \(.browser_download_url)"' "$TMP_DIR/release.json" 2>/dev/null || true
  exit 1
fi

# 8. Download and Extract Binary
ASSET_PATH="$TMP_DIR/asset_$$"
curl --fail --silent --show-error --location --max-time 30 \
  -H "User-Agent: cloudflared-updater" \
  -H "Accept: application/octet-stream" \
  -o "$ASSET_PATH" "$ASSET_URL"

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

# 9. Service Deployment
echo "Stopping service via $SERVICE_MGR..."
if [ "$SERVICE_MGR" = "systemd" ]; then
  systemctl stop "$SERVICE_NAME" || true
else
  rc-service "$SERVICE_NAME" stop || true
fi

echo "Ensuring service is stopped..."
for j in 1 2 3 4 5; do
  PID=$(pidof cloudflared || true)
  if [ -z "$PID" ]; then
    break
  fi
  sleep 1
done

PID=$(pidof cloudflared || true)
if [ -n "$PID" ]; then
  echo "Service refused to stop gracefully. Force-killing process(es): $PID"
  kill -9 $PID || true
  sleep 1
fi

echo "Installing binary to $BIN ..."
if [ -f "$BIN" ]; then
  rm -f "$BIN"
fi

chmod +x "$EXTRACTED_BIN"
mv -f "$EXTRACTED_BIN" "$BIN"
chown root:root "$BIN"
chmod 0755 "$BIN"

# 10. Restart Service
echo "Restarting service..."
if [ "$SERVICE_MGR" = "systemd" ]; then
  systemctl start "$SERVICE_NAME"
else
  rc-service "$SERVICE_NAME" start || true
fi

echo "--- Update Successful! ---"
"$BIN" version
