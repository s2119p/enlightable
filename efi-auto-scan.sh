#!/usr/bin/env bash

# Deep-Analyzed Universal UEFI Auto-Recovery Script (Fixed)
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root (use sudo)."
  exit 1
fi

ESP_MOUNT="/boot/efi"

if [ ! -d "$ESP_MOUNT/EFI" ]; then
    echo "[-] EFI directory not found at $ESP_MOUNT/EFI."
    exit 1
fi

# Dynamically resolve device, partition number, and parent disk
ESP_DEV=$(findmnt -no SOURCE "$ESP_MOUNT")
DEV_NAME=$(basename "$ESP_DEV")

# Read partition number directly from sysfs (100% reliable across all distros)
if [ -f "/sys/class/block/$DEV_NAME/partition" ]; then
    PART_NUM=$(cat "/sys/class/block/$DEV_NAME/partition")
else
    # Fallback for systems without sysfs partition node
    PART_NUM=$(echo "$DEV_NAME" | grep -o '[0-9]*$')
fi

PARENT_DISK=$(lsblk -no PKNAME "$ESP_DEV")
DISK_PATH="/dev/$PARENT_DISK"

echo "============================================================"
echo "[+] Target Drive: $DISK_PATH (Partition $PART_NUM)"
echo "============================================================"

# Read existing UEFI entries
CURRENT_NVRAM=$(efibootmgr -v)

# Blacklist of utilities/helpers that are NOT direct OS bootloaders
EXCLUDE_FILES=("mmx64.efi" "mmia32.efi" "fbx64.efi" "memtest.efi" "memtest86.efi")

# Function to add entry to NVRAM safely using printf (avoids \t and \v mangling)
register_efi() {
    local label="$1"
    local rel_path="$2" # e.g. \EFI\BlissOS\grubx64.efi

    # Exact string match (grep -F) prevents backslash/regex collision
    if echo "$CURRENT_NVRAM" | grep -F -i "$rel_path" > /dev/null; then
        printf "\e[32m[EXISTS]\e[0m %s (%s)\n" "$label" "$rel_path"
    else
        printf "\e[33m[ADDING]\e[0m %s -> %s\n" "$label" "$rel_path"
        efibootmgr -c -d "$DISK_PATH" -p "$PART_NUM" -L "$label" -l "$rel_path"
        # Refresh NVRAM cache
        CURRENT_NVRAM=$(efibootmgr -v)
    fi
}

# 1. SPECIAL CASE: Microsoft Windows
if [ -f "$ESP_MOUNT/EFI/Microsoft/Boot/bootmgfw.efi" ]; then
    register_efi "Windows Boot Manager" "\\EFI\\Microsoft\\Boot\\bootmgfw.efi"
fi

# 2. SPECIAL CASE: Ventoy
if [ -f "$ESP_MOUNT/EFI/ventoy/EFI/BOOT/BOOTX64.EFI" ]; then
    register_efi "Ventoy" "\\EFI\\ventoy\\EFI\\BOOT\\BOOTX64.EFI"
fi

# 3. DYNAMIC SCAN: Iterate through all directories in /EFI/
for DIR in "$ESP_MOUNT"/EFI/*; do
    [ -d "$DIR" ] || continue
    FOLDER=$(basename "$DIR")

    # Skip handled or firmware-reserved folders
    case "$FOLDER" in
        "Microsoft"|"ventoy"|"Boot"|"Insyde") continue ;;
    esac

    TARGET_FILE=""
    LABEL=""

    # Strategy A: Check for BOOTX64.CSV (strip null bytes \0 from UTF-16LE encoding)
    if [ -f "$DIR/BOOTX64.CSV" ]; then
        CSV_DATA=$(tr -d '\0\r' < "$DIR/BOOTX64.CSV" | head -n 1)
        CSV_FILE=$(echo "$CSV_DATA" | cut -d',' -f1)
        CSV_LABEL=$(echo "$CSV_DATA" | cut -d',' -f2)

        if [ -n "$CSV_FILE" ] && [ -f "$DIR/$CSV_FILE" ]; then
            TARGET_FILE="$CSV_FILE"
            LABEL="$CSV_LABEL"
        fi
    fi

    # Strategy B: Prioritize 64-bit loaders for distros without CSV (BlissOS, Arch, etc.)
    if [ -z "$TARGET_FILE" ]; then
        for CANDIDATE in shimx64.efi grubx64.efi systemd-bootx64.efi loader.efi system.efi android.efi bootx64.efi BOOTx64.EFI boot.efi ipxe.efi; do
            if [ -f "$DIR/$CANDIDATE" ]; then
                TARGET_FILE="$CANDIDATE"
                break
            fi
        done
    fi

    # Strategy C: Fallback to any valid .efi file that is not a helper/tool
    if [ -z "$TARGET_FILE" ]; then
        for FILE in "$DIR"/*.efi "$DIR"/*.EFI; do
            [ -f "$FILE" ] || continue
            FNAME=$(basename "$FILE")

            IS_EXCLUDED=0
            for EX in "${EXCLUDE_FILES[@]}"; do
                if [ "${FNAME,,}" == "${EX,,}" ]; then
                    IS_EXCLUDED=1
                    break
                fi
            done

            # Skip 32-bit legacy binaries on x86_64
            if [[ "${FNAME,,}" =~ ia32\.efi$ ]]; then
                IS_EXCLUDED=1
            fi

            if [ "$IS_EXCLUDED" -eq 0 ]; then
                TARGET_FILE="$FNAME"
                break
            fi
        done
    fi

    # Register valid bootloaders
    if [ -n "$TARGET_FILE" ]; then
        if [ -z "$LABEL" ]; then
            LABEL="$(tr '[:lower:]' '[:upper:]' <<< ${FOLDER:0:1})${FOLDER:1}"
        fi
        register_efi "$LABEL" "\\EFI\\$FOLDER\\$TARGET_FILE"
    fi
done

echo "============================================================"
echo "[+] Scan completed successfully."
echo "============================================================"
