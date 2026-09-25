#!/usr/bin/env bash

# Interactive Universal UEFI Boot Entry Manager
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

if [ -f "/sys/class/block/$DEV_NAME/partition" ]; then
    PART_NUM=$(cat "/sys/class/block/$DEV_NAME/partition")
else
    PART_NUM=$(echo "$DEV_NAME" | grep -o '[0-9]*$')
fi

PARENT_DISK=$(lsblk -no PKNAME "$ESP_DEV")
DISK_PATH="/dev/$PARENT_DISK"

echo "============================================================"
echo "[+] Target Drive: $DISK_PATH (Partition $PART_NUM)"
echo "============================================================"

CURRENT_NVRAM=$(efibootmgr -v)
EXCLUDE_FILES=("mmx64.efi" "mmia32.efi" "fbx64.efi" "memtest.efi" "memtest86.efi")

# Interactive registration function
prompt_and_register() {
    local default_label="$1"
    local rel_path="$2"

    echo ""
    echo "------------------------------------------------------------"
    printf "Detected EFI: \e[36m%s\e[0m\n" "$rel_path"

    # Check if already present in NVRAM
    if echo "$CURRENT_NVRAM" | grep -F -i "$rel_path" > /dev/null; then
        printf "Status: \e[32m[ALREADY REGISTERED IN UEFI]\e[0m\n"
        read -r -p "Do you want to re-add / add another entry for this? [y/N]: " CHOICE < /dev/tty
        if [[ ! "$CHOICE" =~ ^[Yy]$ ]]; then
            echo "Skipping..."
            return
        fi
    else
        printf "Status: \e[33m[NOT IN UEFI MENU]\e[0m\n"
        read -r -p "Add this entry to UEFI boot menu? [Y/n]: " CHOICE < /dev/tty
        if [[ "$CHOICE" =~ ^[Nn]$ ]]; then
            echo "Skipping..."
            return
        fi
    fi

    # Prompt for label name
    read -r -p "Enter boot menu label [Default: $default_label]: " CUSTOM_LABEL < /dev/tty
    FINAL_LABEL="${CUSTOM_LABEL:-$default_label}"

    printf "Registering: \e[32m%s\e[0m -> %s\n" "$FINAL_LABEL" "$rel_path"
    efibootmgr -c -d "$DISK_PATH" -p "$PART_NUM" -L "$FINAL_LABEL" -l "$rel_path"
    CURRENT_NVRAM=$(efibootmgr -v)
}

# 1. SPECIAL CASE: Microsoft Windows
if [ -f "$ESP_MOUNT/EFI/Microsoft/Boot/bootmgfw.efi" ]; then
    prompt_and_register "Windows Boot Manager" "\\EFI\\Microsoft\\Boot\\bootmgfw.efi"
fi

# 2. SPECIAL CASE: Ventoy
if [ -f "$ESP_MOUNT/EFI/ventoy/EFI/BOOT/BOOTX64.EFI" ]; then
    prompt_and_register "Ventoy" "\\EFI\\ventoy\\EFI\\BOOT\\BOOTX64.EFI"
fi

# 3. DYNAMIC SCAN
for DIR in "$ESP_MOUNT"/EFI/*; do
    [ -d "$DIR" ] || continue
    FOLDER=$(basename "$DIR")

    case "$FOLDER" in
        "Microsoft"|"ventoy"|"Boot"|"Insyde") continue ;;
    esac

    TARGET_FILE=""
    LABEL=""

    # Strategy A: Check BOOTX64.CSV
    if [ -f "$DIR/BOOTX64.CSV" ]; then
        CSV_DATA=$(tr -d '\0\r' < "$DIR/BOOTX64.CSV" | head -n 1)
        CSV_FILE=$(echo "$CSV_DATA" | cut -d',' -f1)
        CSV_LABEL=$(echo "$CSV_DATA" | cut -d',' -f2)

        if [ -n "$CSV_FILE" ] && [ -f "$DIR/$CSV_FILE" ]; then
            TARGET_FILE="$CSV_FILE"
            LABEL="$CSV_LABEL"
        fi
    fi

    # Strategy B: Prioritize standard 64-bit loaders
    if [ -z "$TARGET_FILE" ]; then
        for CANDIDATE in shimx64.efi grubx64.efi systemd-bootx64.efi loader.efi system.efi android.efi bootx64.efi BOOTx64.EFI boot.efi ipxe.efi; do
            if [ -f "$DIR/$CANDIDATE" ]; then
                TARGET_FILE="$CANDIDATE"
                break
            fi
        done
    fi

    # Strategy C: First non-excluded .efi file
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

            if [[ "${FNAME,,}" =~ ia32\.efi$ ]]; then
                IS_EXCLUDED=1
            fi

            if [ "$IS_EXCLUDED" -eq 0 ]; then
                TARGET_FILE="$FNAME"
                break
            fi
        done
    fi

    if [ -n "$TARGET_FILE" ]; then
        if [ -z "$LABEL" ]; then
            LABEL="$(tr '[:lower:]' '[:upper:]' <<< ${FOLDER:0:1})${FOLDER:1}"
        fi
        prompt_and_register "$LABEL" "\\EFI\\$FOLDER\\$TARGET_FILE"
    fi
done

echo ""
echo "============================================================"
echo "[+] Configuration finished. Current UEFI Boot Entries:"
echo "============================================================"
efibootmgr
