#!/bin/sh
# ==============================================================================
# Universal Direct-Stream Rootfs Backup (Alpine & Armbian / Debian)
# Features: 0 MB Disk Cache, RAM Spooling, Interrupt Auto-Clean, Subshell Safe
# ==============================================================================

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

# 3. Detect OS and Target Names
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

# 4. Determine RAM-backed temporary directory (Prevents eMMC writes)
if [ -d /dev/shm ]; then
    RAM_TMP="/dev/shm"
elif [ -d /run ]; then
    RAM_TMP="/run"
else
    RAM_TMP="/tmp"
fi

EXCLUDES="${RAM_TMP}/backup_excludes_$$.txt"

# 5. Trap interrupts (Ctrl+C / Kill) to wipe any residue instantly
cleanup() {
    exit_code=$?
    trap - EXIT INT TERM HUP
    echo ""
    echo "[*] Cleaning temporary files and buffers..."
    rm -f "$EXCLUDES"
    rm -f "${RAM_TMP}/rclone-spool*" 2>/dev/null || true
    rm -f /tmp/rclone-spool* 2>/dev/null || true
    
    if [ $exit_code -ne 0 ]; then
        echo "[!] Backup aborted or interrupted. No disk residue left behind."
    fi
    exit $exit_code
}
trap cleanup EXIT INT TERM HUP

echo "============================================================"
echo "   Universal Direct Stream Backup (${OS_NAME})"
echo "   (RAM Spooling Active: ${RAM_TMP} | 0 MB Disk Cache)"
echo "============================================================"

# --- 6. Interactive Prompts ---

# Prompt 1: Source
printf "1. Source directory to backup [Default: /]: "
if [ -c /dev/tty ]; then
    read -r INPUT_SRC < /dev/tty
else
    read -r INPUT_SRC
fi
SRC="${INPUT_SRC:-/}"

if [ ! -d "$SRC" ]; then
    echo "[-] Error: Source directory '$SRC' does not exist!" >&2
    exit 1
fi

# Prompt 2: Include /boot
printf "2. Include /boot directory? (y/N) [Default: N]: "
if [ -c /dev/tty ]; then
    read -r INPUT_BOOT < /dev/tty
else
    read -r INPUT_BOOT
fi

case "$INPUT_BOOT" in
    [yY][eE][sS]|[yY])
        INCLUDE_BOOT=1
        BOOT_LABEL="BOOT"
        ;;
    *)
        INCLUDE_BOOT=0
        BOOT_LABEL="NOBOOT"
        ;;
esac

# Prompt 3: Remote Destination (Rclone path)
DEFAULT_DEST="LXCsamba:lnvo_Samba/lnvoBkp/LnvoBackup/${OS_TAG}"
printf "3. Enter Rclone remote path [Default: %s]: " "$DEFAULT_DEST"
if [ -c /dev/tty ]; then
    read -r INPUT_DEST < /dev/tty
else
    read -r INPUT_DEST
fi
DEST="${INPUT_DEST:-$DEFAULT_DEST}"

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
echo " Temp Buffer:  $RAM_TMP (In-Memory)"
echo "----------------------------"
echo "Starting direct network compression and stream..."

# --- 7. Generate Watertight Exclusion List ---
cat << 'EOF' > "$EXCLUDES"
./proc
./proc/*
proc
proc/*
./sys
./sys/*
sys
sys/*
./dev
./dev/*
dev
dev/*
./run
./run/*
run
run/*
./tmp
./tmp/*
tmp
tmp/*
./media
./media/*
media
media/*
./mnt
./mnt/*
mnt
mnt/*
./lost+found
lost+found
./var/cache
./var/cache/*
var/cache/*
./var/tmp
./var/tmp/*
var/tmp/*
./root/.cache
./root/.cache/*
root/.cache/*
*.tar.gz
EOF

# Exclude boot if opted out
if [ "$INCLUDE_BOOT" -eq 0 ]; then
    cat << 'EOF' >> "$EXCLUDES"
./boot
./boot/*
boot
boot/*
EOF
fi

# --- 8. Execute Direct Network Stream ---
# -v writes live file progress to your screen (stderr)
# stdout is piped directly into rclone rcat using RAM buffer
tar --numeric-owner -cpvzf - -X "$EXCLUDES" -C "$SRC" . | \
    rclone rcat \
        --temp-dir "$RAM_TMP" \
        --timeout 15s \
        --contimeout 15s \
        "$TARGET_REMOTE"

echo ""
echo "------------------------------------------------------------"
echo " [✓] Direct Stream Backup Complete!"
echo " Remote Target: $TARGET_REMOTE"
echo "------------------------------------------------------------"
