#!/bin/sh
# ==============================================================================
# Universal Root Backup Script for Alpine & Armbian / Debian
# ==============================================================================

set -e

# 1. Root privilege check
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root to preserve file permissions." >&2
    exit 1
fi

# 2. Detect OS Name
if [ -f /etc/alpine-release ]; then
    OS_NAME="Alpine"
elif [ -f /etc/armbian-release ]; then
    OS_NAME="Armbian"
elif [ -f /etc/debian_version ]; then
    OS_NAME="Debian"
else
    OS_NAME="Linux"
fi

HOSTNAME=$(hostname 2>/dev/null || echo "box")
DATE=$(date +%Y-%m-%d_%H-%M)

echo "============================================================"
echo "    Universal System Root Backup (${OS_NAME})"
echo "============================================================"

# 3. Choice: Source Directory
printf "Enter Source directory to backup [Default: /]: "
read -r INPUT_SRC
SRC="${INPUT_SRC:-/}"

# Ensure source exists
if [ ! -d "$SRC" ]; then
    echo "[-] Error: Source directory '$SRC' does not exist!" >&2
    exit 1
fi

# 4. Choice: Destination Directory
printf "Enter Destination directory to save backup [Default: /]: "
read -r INPUT_DEST
DEST="${INPUT_DEST:-/}"

# Ensure destination exists or create it
mkdir -p "$DEST"

# 5. Choice: Include /boot
printf "Include /boot in the backup? (y/N) [Default: N]: "
read -r INPUT_BOOT
case "$INPUT_BOOT" in
    [yY][eE][sS]|[yY])
        INCLUDE_BOOT=1
        ;;
    *)
        INCLUDE_BOOT=0
        ;;
esac

# 6. Define output filename
# Strip trailing slash from DEST if present
DEST_CLEAN=$(echo "$DEST" | sed 's:/*$::')
FILENAME="${DEST_CLEAN}/${HOSTNAME}_${OS_NAME}_backup_${DATE}.tar.gz"

echo ""
echo "--- Backup Configuration ---"
echo " OS:           $OS_NAME"
echo " Source:       $SRC"
echo " Destination:  $FILENAME"
if [ "$INCLUDE_BOOT" -eq 1 ]; then
    echo " Boot Folder:  INCLUDED"
else
    echo " Boot Folder:  EXCLUDED"
fi
echo "-----------------------------"
echo "Starting backup process..."

# 7. Generate temporary exclude file
EXCLUDES="/tmp/backup_excludes_$$.txt"

cat <<EOF > "$EXCLUDES"
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

# Exclude boot if user chose 'N'
if [ "$INCLUDE_BOOT" -eq 0 ]; then
    echo "./boot/*" >> "$EXCLUDES"
    echo "boot/*" >> "$EXCLUDES"
fi

# 8. Execute the backup
# -p preserves permissions
# --numeric-owner preserves exact UID/GIDs across different distros
tar --numeric-owner -cvpzf "$FILENAME" -X "$EXCLUDES" -C "$SRC" .

# 9. Cleanup temporary files
rm -f "$EXCLUDES"

echo "------------------------------------------------------------"
echo "Backup Complete!"
echo "Size:     $(du -sh "$FILENAME" | awk '{print $1}')"
echo "Location: $FILENAME"
echo "------------------------------------------------------------"
