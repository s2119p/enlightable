#!/bin/sh
# ==============================================================================
# Universal Direct Stream Rootfs Backup (Alpine & Armbian / Debian)
# Streams tar -> rclone rcat without saving any temporary files on local disk
# ==============================================================================

set -e

# Helper to read from terminal even inside piped subshells
prompt_read() {
    prompt_text="$1"
    default_val="$2"
    printf "%s" "$prompt_text"
    if [ -c /dev/tty ]; then
        read -r input < /dev/tty
    else
        read -r input
    fi
    echo "${input:-$default_val}"
}

# 1. Root check
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root." >&2
    exit 1
fi

# 2. Check if rclone is installed
if ! command -v rclone >/dev/null 2>&1; then
    echo "[-] Error: rclone is not installed. Please install rclone first." >&2
    exit 1
fi

# 3. Detect OS
if [ -f /etc/alpine-release ]; then
    OS_NAME="Alpine"
    OS_TAG="alpine_rootfs"
elif [ -f /etc/armbian-release ]; then
    OS_NAME="Armbian"
    OS_TAG="armbian_rootfs"
elif [ -f /etc/debian_version ]; then
    OS_NAME="Debian"
    OS_TAG="debian_rootfs"
else
    OS_NAME="Linux"
    OS_TAG="linux_rootfs"
fi

HOSTNAME=$(hostname 2>/dev/null || echo "box")
DATE=$(date +%Y-%m-%d_%H-%M)

echo "============================================================"
echo "   Universal Direct Stream Backup (${OS_NAME})"
echo "   (0 MB Local Disk Space Used - Direct Stream to Remote)"
echo "============================================================"

# --- 4. Interactive Options ---

# Option 1: Source directory
SRC=$(prompt_read "1. Source directory to backup [Default: /]: " "/")
if [ ! -d "$SRC" ]; then
    echo "[-] Error: Source directory '$SRC' does not exist!" >&2
    exit 1
fi

# Option 2: Include /boot
BOOT_CHOICE=$(prompt_read "2. Include /boot directory? (y/N) [Default: N]: " "N")
case "$BOOT_CHOICE" in
    [yY][eE][sS]|[yY])
        INCLUDE_BOOT=1
        BOOT_LABEL="BOOT"
        ;;
    *)
        INCLUDE_BOOT=0
        BOOT_LABEL="NOBOOT"
        ;;
esac

# Option 3: Remote Destination (Rclone path)
DEFAULT_DEST="LXCsamba:lnvo_Samba/lnvoBkp/LnvoBackup/${OS_TAG}"
DEST=$(prompt_read "3. Enter Rclone remote path [Default: $DEFAULT_DEST]: " "$DEFAULT_DEST")

# Clean destination trailing slash
DEST_CLEAN=$(echo "$DEST" | sed 's:/*$::')
ARCHIVE_NAME="${HOSTNAME}_${OS_NAME}_backup_${DATE}-${BOOT_LABEL}.tar.gz"
TARGET_REMOTE="${DEST_CLEAN}/${ARCHIVE_NAME}"

echo ""
echo "--- Stream Configuration ---"
echo " OS:           $OS_NAME"
echo " Source:       $SRC"
echo " Boot Folder:  $([ "$INCLUDE_BOOT" -eq 1 ] && echo 'INCLUDED' || echo 'EXCLUDED')"
echo " Destination:  $TARGET_REMOTE"
echo "----------------------------"
echo "Starting direct network compression and stream..."

# --- 5. Generate Exclusion List in /tmp (RAM) ---
EXCLUDES="/tmp/stream_excludes_$$.txt"
trap 'rm -f "$EXCLUDES"' EXIT INT TERM

cat << 'EOF' > "$EXCLUDES"
./proc/*
proc/*
./sys/*
sys/*
./dev/*
dev/*
./run/*
run/*
./tmp/*
tmp/*
./var/cache/*
var/cache/*
./var/tmp/*
var/tmp/*
./mnt/*
mnt/*
./media/*
media/*
./lost+found
lost+found
*.tar.gz
EOF

# Exclude boot if opted out
if [ "$INCLUDE_BOOT" -eq 0 ]; then
    echo "./boot/*" >> "$EXCLUDES"
    echo "boot/*" >> "$EXCLUDES"
fi

# --- 6. Direct Stream: tar -> rclone rcat ---
tar --numeric-owner -cpzf - -X "$EXCLUDES" -C "$SRC" . | rclone rcat "$TARGET_REMOTE"

echo ""
echo "------------------------------------------------------------"
echo " Direct Stream Backup Complete!"
echo " Remote Target: $TARGET_REMOTE"
echo "------------------------------------------------------------"
