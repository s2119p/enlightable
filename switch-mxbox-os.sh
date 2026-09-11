#!/bin/sh
set -e

EXT_DIR="/boot/extlinux"
ACTIVE="$EXT_DIR/extlinux.conf"
ARMBIAN="$EXT_DIR/extlinux.conf-Armbian"
ALPINE="$EXT_DIR/extlinux.conf-Alpine"
TMP="$EXT_DIR/extlinux.conf.tmp.$$"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (or with sudo)." >&2
    exit 1
fi

# Ensure directory exists
if [ ! -d "$EXT_DIR" ]; then
    echo "[-] Error: Directory $EXT_DIR does not exist." >&2
    exit 1
fi

# Ensure active file exists
if [ ! -f "$ACTIVE" ]; then
    echo "[-] Error: $ACTIVE is missing." >&2
    exit 1
fi

# Case 1: Alpine is active, switch to Armbian
if [ -f "$ARMBIAN" ]; then
    echo "[*] Currently active: Alpine"
    echo "[*] Switching to: Armbian..."
    
    mv "$ACTIVE" "$TMP"
    mv "$ARMBIAN" "$ACTIVE"
    mv "$TMP" "$ALPINE"
    sync

    echo "[+] Done. Active OS is now Armbian (next boot will load Armbian)."

# Case 2: Armbian is active, switch to Alpine
elif [ -f "$ALPINE" ]; then
    echo "[*] Currently active: Armbian"
    echo "[*] Switching to: Alpine..."
    
    mv "$ACTIVE" "$TMP"
    mv "$ALPINE" "$ACTIVE"
    mv "$TMP" "$ARMBIAN"
    sync

    echo "[+] Done. Active OS is now Alpine (next boot will load Alpine)."

else
    echo "[-] Error: Neither $ARMBIAN nor $ALPINE was found." >&2
    echo "Current contents of $EXT_DIR:"
    ls -la "$EXT_DIR"
    exit 1
fi
