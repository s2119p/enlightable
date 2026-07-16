#!/bin/sh
set -euo pipefail

REPO="usememos/memos"
BIN_DIR="/usr/local/bin"
BIN="$BIN_DIR/memos"
DATA_DIR="/var/opt/memos"
VERSION_FILE="$DATA_DIR/.version"
TMP_DIR="/tmp/memos_updater"
RETRIES=3

echo "--- Starting Memos Update & Installation Check ---"

# 1. Root Privileges Check
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root to manage services and packages."
  exit 1
fi

# 2. OS & Package Manager Detection
if [ -f /etc/alpine-release ]; then
  OS="alpine"
  PKG_MGR="apk"
elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
  OS="debian"
  PKG_MGR="apt"
else
  OS="unknown"
  PKG_MGR="unknown"
fi

# 3. Detect Service Manager
if command -v systemctl > /dev/null 2>&1; then
  SERVICE_MGR="systemd"
  SERVICE_NAME="memos"
elif command -v rc-service > /dev/null 2>&1; then
  SERVICE_MGR="openrc"
  SERVICE_NAME="memos"
else
  echo "Error: No supported service manager (systemd or openrc) found."
  exit 1
fi

# 4. Dependency Validation & Automatic Installation
for cmd in curl jq tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Dependency '$cmd' is missing. Attempting to install..."
    if [ "$PKG_MGR" = "apk" ]; then
      apk update && apk add "$cmd" ca-certificates
    elif [ "$PKG_MGR" = "apt" ]; then
      apt-get update && apt-get install -y "$cmd" ca-certificates
    else
      echo "Error: Unsupported package manager. Please install '$cmd' manually."
      exit 1
    fi
  fi
done

# 5. Check Current Version
CURRENT_VERSION="none"
if [ -x "$BIN" ]; then
  # Attempt to extract version from binary
  RAW_VER=$("$BIN" --version 2>/dev/null || "$BIN" version 2>/dev/null || true)
  CURRENT_VERSION=$(printf '%s\n' "$RAW_VER" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
  
  # Fallback to metadata file if binary output cannot be parsed
  if [ -z "$CURRENT_VERSION" ] && [ -f "$VERSION_FILE" ]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE")
  fi
  
  if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="corrupted"
  fi
  echo "Current Installed Version: $CURRENT_VERSION"
else
  echo "Memos is not currently installed."
fi

mkdir -p "$TMP_DIR"
mkdir -p "$DATA_DIR"
CURL_ERR_LOG="$TMP_DIR/curl_error_$$"
trap 'rm -rf "$TMP_DIR" 2>/dev/null || true' EXIT

# 6. Fetch Latest Release Version from GitHub API
i=0
LATEST_TAG=""
while [ $i -lt $RETRIES ] && [ -z "$LATEST_TAG" ]; do
  if curl --fail --show-error --location --max-time 30 \
    -H "User-Agent: memos-updater" \
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
  echo "Error: Could not retrieve version metadata from GitHub."
  exit 1
fi

LATEST_VERSION="$LATEST_TAG"

# 7. Compare Versions
CLEAN_CURRENT=$(printf '%s\n' "$CURRENT_VERSION" | sed 's/^v//')
CLEAN_LATEST=$(printf '%s\n' "$LATEST_VERSION" | sed 's/^v//')

if [ "$CLEAN_CURRENT" = "$CLEAN_LATEST" ]; then
  echo "Memos is already up to date ($CURRENT_VERSION)."
  exit 0
fi

# 8. Determine Architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) SEARCH_TERM="memos-linux-amd64" ;;
  aarch64|arm64) SEARCH_TERM="memos-linux-arm64" ;;
  *) echo "Error: Unsupported architecture $ARCH"; exit 1 ;;
esac

echo "Updating to $LATEST_VERSION ($SEARCH_TERM)..."

# 9. Resolve Download URL
i=0
ASSET_URL=""
while [ $i -lt $RETRIES ] && [ -z "$ASSET_URL" ]; do
  # Match assets containing the search term, excluding validation files like .sha256 or .txt
  ASSET_URL=$(jq -r --arg term "$SEARCH_TERM" '.assets[] | select(.name | test($term)) | select(.name | test("\\.(sha256|md5|txt)$") | not) | .browser_download_url' "$TMP_DIR/release.json" 2>/dev/null | head -n1 || true)
  i=$((i+1))
  [ -n "$ASSET_URL" ] || sleep 1
done

echo "Resolved ASSET_URL: '$ASSET_URL'"

if [ -z "$ASSET_URL" ]; then
  echo "Error: Could not find matching release asset for '$SEARCH_TERM'."
  exit 1
fi

# 10. Download and Extract Binary
ASSET_PATH="$TMP_DIR/asset_$$"
curl --fail --silent --show-error --location --max-time 30 \
  -H "User-Agent: memos-updater" \
  -H "Accept: application/octet-stream" \
  -o "$ASSET_PATH" "$ASSET_URL"

EXTRACT_DIR="$TMP_DIR/tmp_extract_$$"
mkdir -p "$EXTRACT_DIR"

case "$ASSET_URL" in
  *.tar.gz|*.tgz)
    tar -xzf "$ASSET_PATH" -C "$EXTRACT_DIR"
    EXTRACTED_BIN=$(find "$EXTRACT_DIR" -type f -name "memos" | head -n1 || true)
    ;;
  *)
    EXTRACTED_BIN="$ASSET_PATH"
    chmod +x "$EXTRACTED_BIN"
    ;;
esac

if [ -z "$EXTRACTED_BIN" ] || [ ! -f "$EXTRACTED_BIN" ]; then
  echo "Error: Could not locate extracted 'memos' binary."
  exit 1
fi

# 11. Stop Existing Service (If Installed)
SERVICE_EXISTS=false
if [ "$SERVICE_MGR" = "systemd" ]; then
  if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
    SERVICE_EXISTS=true
    echo "Stopping service via systemd..."
    systemctl stop "$SERVICE_NAME" || true
  fi
else
  if [ -f "/etc/init.d/$SERVICE_NAME" ]; then
    SERVICE_EXISTS=true
    echo "Stopping service via openrc..."
    rc-service "$SERVICE_NAME" stop || true
  fi
fi

# Ensure process is completely dead
if [ "$SERVICE_EXISTS" = true ]; then
  for j in 1 2 3; do
    PID=$(pidof memos || true)
    [ -z "$PID" ] && break
    sleep 1
  done
  PID=$(pidof memos || true)
  if [ -n "$PID" ]; then
    echo "Forcing process termination: $PID"
    kill -9 $PID || true
  fi
fi

# 12. Deploy Binary
echo "Installing binary to $BIN ..."
if [ -f "$BIN" ]; then
  rm -f "$BIN"
fi

chmod +x "$EXTRACTED_BIN"
mv -f "$EXTRACTED_BIN" "$BIN"
chown root:root "$BIN"
chmod 0755 "$BIN"

# 13. Install Service File if Not Already Configured
if [ "$SERVICE_EXISTS" = false ]; then
  echo "Installing background service configuration..."
  
  if [ "$SERVICE_MGR" = "systemd" ]; then
    cat <<EOF > /etc/systemd/system/memos.service
[Unit]
Description=Memos Service
After=network.target

[Service]
Type=simple
ExecStart=$BIN --mode prod --port 5230 --data $DATA_DIR
WorkingDirectory=$DATA_DIR
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable memos
    
  elif [ "$SERVICE_MGR" = "openrc" ]; then
    cat <<EOF > /etc/init.d/memos
#!/sbin/openrc-run

name="memos"
description="Memos service"
command="$BIN"
command_args="--mode prod --port 5230 --data $DATA_DIR"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
working_dir="$DATA_DIR"

depend() {
    need net
}

start_pre() {
    checkpath -d -m 0755 -o root:root $DATA_DIR
}
EOF
    chmod +x /etc/init.d/memos
    rc-update add memos default
  fi
fi

# 14. Start/Restart Service
echo "Starting service..."
if [ "$SERVICE_MGR" = "systemd" ]; then
  systemctl start "$SERVICE_NAME"
else
  rc-service "$SERVICE_NAME" start || true
fi

# Store version metadata for accurate future comparisons
echo "$LATEST_VERSION" > "$VERSION_FILE"

echo "--- Update Successful! ---"
echo "Memos has been updated to: $LATEST_VERSION"
