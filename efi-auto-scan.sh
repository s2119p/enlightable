#!/usr/bin/env bash

# Deep-Analyzed Universal UEFI Auto-Recovery Script
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run as root (use sudo)."
  exit 1
fi

ESP_MOUNT="/boot/efi"

if [ ! -d "$ESP_MOUNT/EFI" ]; then
    echo "[-] EFI directory not found at $ESP_MOUNT/EFI."
    exit 1
fi

# Dynamically resolve parent disk and partition number
ESP_DEV=$(findmnt -no SOURCE "$ESP_MOUNT")
PARENT_DISK=$(lsblk -no PKNAME "$ESP_DEV")
PART_NUM=$(lsblk -no PARTNUM "$ESP_DEV")
DISK_PATH="/dev/$PARENT_DISK"

echo "============================================================"
echo "[+] Target Drive: $DISK_PATH (Partition $PART_NUM)"
echo "============================================================"

# Read existing UEFI entries
CURRENT_NVRAM=$(efibootmgr -v)

# Blacklist of utilities/helpers that are NOT direct OS bootloaders
EXCLUDE_FILES=("mmx64.efi" "mmia32.efi" "fbx64.efi" "memtest.efi" "memtest86.efi")

# Function to add entry to NVRAM
register_efi() {
    local label="$1"
    local rel_path="$2" # e.g. \EFI\BlissOS\grubx64.efi

    # Normalize search pattern for efibootmgr check
    local search_pattern
    search_pattern=$(echo "$rel_path" | sed 's/\\/\\\\/g')

    if echo "$CURRENT_NVRAM" | grep -iq "$search_pattern"; then
        echo -e "\e[32m[EXISTS]\e[0m $label ($rel_path)"
    else
        echo -e "\e[33m[ADDING]\e[0m $label -> $rel_path"
        efibootmgr -c -d "$DISK_PATH" -p "$PART_NUM" -L "$label" -l "$rel_path"
    fi
}

# 1. SPECIAL CASE: Microsoft Windows (nested under /EFI/Microsoft/Boot/)
if [ -f "$ESP_MOUNT/EFI/Microsoft/Boot/bootmgfw.efi" ]; then
    register_efi "Windows Boot Manager" "\\EFI\\Microsoft\\Boot\\bootmgfw.efi"
fi

# 2. SPECIAL CASE: Ventoy (nested under /EFI/ventoy/EFI/BOOT/ or root)
if [ -f "$ESP_MOUNT/EFI/ventoy/EFI/BOOT/BOOTX64.EFI" ]; then
    register_efi "Ventoy" "\\EFI\\ventoy\\EFI\\BOOT\\BOOTX64.EFI"
fi

# 3. DYNAMIC SCAN: Iterate through all directories in /EFI/
for DIR in "$ESP_MOUNT"/EFI/*; do
    [ -d "$DIR" ] || continue
    FOLDER=$(basename "$DIR")

    # Skip folders already handled or reserved
    case "$FOLDER" in
        "Microsoft"|"ventoy"|"Boot"|"Insyde") continue ;;
    esac

    TARGET_FILE=""
    LABEL=""

    # Strategy A: Check for BOOTX64.CSV (used by Tuxedo, Ubuntu, Mint, Fedora, etc.)
    if [ -f "$DIR/BOOTX64.CSV" ]; then
        CSV_DATA=$(head -n 1 "$DIR/BOOTX64.CSV" | tr -d '\r')
        CSV_FILE=$(echo "$CSV_DATA" | cut -d',' -f1)
        CSV_LABEL=$(echo "$CSV_DATA" | cut -d',' -f2)

        if [ -n "$CSV_FILE" ] && [ -f "$DIR/$CSV_FILE" ]; then
            TARGET_FILE="$CSV_FILE"
            LABEL="$CSV_LABEL"
        fi
    fi

    # Strategy B: Prioritize 64-bit loaders for distros without CSV (BlissOS, Arch, etc.)
    if [ -z "$TARGET_FILE" ]; then
        # Check standard EFI loaders in order of preference
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

            # Check if this file is in the exclude list
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

    # If an EFI bootloader was resolved, register it
    if [ -n "$TARGET_FILE" ]; then
        if [ -z "$LABEL" ]; then
            # Capitalize directory name for label
            LABEL="$(tr '[:lower:]' '[:upper:]' <<< ${FOLDER:0:1})${FOLDER:1}"
        fi
        register_efi "$LABEL" "\\EFI\\$FOLDER\\$TARGET_FILE"
    fi
done

echo "============================================================"
echo "[+] Scan completed successfully."
echo "============================================================"
