#!/bin/sh

# Configuration
INSTALL_PATH="/usr/local/bin/copyparty-en.py"
SERVICE_NAME="copyparty"
DOWNLOAD_URL="https://github.com/9001/copyparty/releases/latest/download/copyparty-en.py"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Ensure curl is installed to perform web requests
if ! command -v curl >/dev/null 2>&1; then
    echo "curl is not installed. Installing curl..."
    apk add --no-cache curl || { echo "Failed to install curl. Exiting." >&2; exit 1; }
fi

# Ensure python3 is installed
if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is not installed. Installing python3..."
    apk add --no-cache python3 || { echo "Failed to install python3. Exiting." >&2; exit 1; }
fi

# 1. Always perform the online version check first
echo "Checking for the latest version of copyparty on GitHub..."
LATEST_VERSION=$(curl -s "https://api.github.com/repos/9001/copyparty/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | tr -d 'vV')

if [ -z "$LATEST_VERSION" ]; then
    echo "Error: Failed to fetch the latest version from GitHub." >&2
    exit 1
fi

# Helper function to stop the rc-service safely if it exists
stop_service_if_exists() {
    if command -v rc-service >/dev/null 2>&1 && rc-service -e "$SERVICE_NAME"; then
        echo "Stopping OpenRC service '$SERVICE_NAME'..."
        rc-service "$SERVICE_NAME" stop
    fi
}

# Helper function to start the rc-service safely if it exists
start_service_if_exists() {
    if command -v rc-service >/dev/null 2>&1 && rc-service -e "$SERVICE_NAME"; then
        echo "Starting OpenRC service '$SERVICE_NAME'..."
        rc-service "$SERVICE_NAME" start
    fi
}

# 2. Check if copyparty-en.py is installed
if [ ! -f "$INSTALL_PATH" ]; then
    echo "copyparty-en.py is not installed."
    
    # Stop the service if there is any orphan/pre-existing configuration
    stop_service_if_exists

    # Perform fresh installation
    echo "Downloading and installing copyparty v$LATEST_VERSION..."
    curl -L -o "$INSTALL_PATH" "$DOWNLOAD_URL"
    chmod +x "$INSTALL_PATH"

    start_service_if_exists
    echo "Installation completed."
else
    # Parse the locally installed version
    LOCAL_VERSION=$(python3 "$INSTALL_PATH" --version 2>/dev/null | head -n 1 | tr ' ' '\n' | grep -E '^[vV]?[0-9]+' | tr -d 'vV' | head -n 1)

    if [ -z "$LOCAL_VERSION" ]; then
        echo "Warning: Could not parse local version. Treating as modified/unknown and forcing clean install."
        LOCAL_VERSION="unknown"
    fi

    # 3. Compare versions
    if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ]; then
        # Same version: do not update
        echo "already the updated version ....... $LOCAL_VERSION"
    else
        # Different/newer version found: perform update
        echo "New version found: $LATEST_VERSION (installed version: $LOCAL_VERSION)"
        
        # Stop the rc-service of copyparty before updating if there is any
        stop_service_if_exists

        # Delete the old version first
        echo "Deleting the old version..."
        rm -f "$INSTALL_PATH"

        # Download the new version
        echo "Downloading and installing copyparty v$LATEST_VERSION..."
        curl -L -o "$INSTALL_PATH" "$DOWNLOAD_URL"
        chmod +x "$INSTALL_PATH"

        # Start the service again if it exists
        start_service_if_exists
        echo "Update completed successfully."
    fi
fi