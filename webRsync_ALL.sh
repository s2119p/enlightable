#!/bin/bash

# ─── CONFIGURATION ───────────────────────────────────────────────
GDRIVE="/mnt/Moxprox01/webpage/html/"
WEBSERVER="/var/www/html/"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}==========================================${NC}"
echo -e "${YELLOW}     High-Speed Cloud Sync & Hardening    ${NC}"
echo -e "${YELLOW}==========================================${NC}"

# ─── STEP 0: AUTO-DETECTION ──────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_ID="$ID"
else
    OS_NAME="Unknown Linux"
    OS_ID="unknown"
fi

ARCH=$(uname -m)

# Resolve Web User/Group across Alpine / Debian / Armbian
if id "www-data" &>/dev/null; then
    WEB_USER="www-data"
    WEB_GROUP="www-data"
elif id "apache" &>/dev/null; then
    WEB_USER="apache"
    WEB_GROUP="apache"
elif id "sudhir" &>/dev/null; then
    WEB_USER="sudhir"
    WEB_GROUP="sudhir"
else
    WEB_USER="root"
    WEB_GROUP="root"
fi

# High-speed flags:
# -r: recursive
# -t: preserve timestamps (essential for note mtime sorting!)
# -u: update (skip files that are newer on the destination)
# -v: verbose
# --modify-window=2: ignores FAT/FUSE 2-second timestamp drift on Google Drive
RSYNC_OPTS="-rtuv --modify-window=2 --exclude=.*.tmp --exclude=notes_data/ --exclude=note-data/"

echo -e "   OS Detected  : ${GREEN}$OS_NAME ($ARCH)${NC}"
echo -e "   Web Target   : ${GREEN}$WEB_USER:$WEB_GROUP${NC}"
echo -e "   Mode         : ${GREEN}FUSE/Gdrive Optimized (Fast Timestamp Window)${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

# ─── STEP 1: PRE-FLIGHT CHECKS ───────────────────────────────────
if [ ! -d "$WEBSERVER" ]; then
    mkdir -p "$WEBSERVER"
fi

# Verify mount point is active
if ! mountpoint -q "/mnt/Moxprox01"; then
    echo -e "${RED}❌ ERROR: Mount point /mnt/Moxprox01 is NOT mounted!${NC}"
    echo -e "${RED}Aborting to prevent disk writes into the mount root.${NC}"
    exit 1
fi

if [ ! -d "$GDRIVE" ]; then
    mkdir -p "$GDRIVE"
fi

# ─── STEP 2: BIDIRECTIONAL FAST SYNC ──────────────────────────────
# 1. PULL: Update local with newer cloud files
echo -e "\n${CYAN}📥 Pulling: GDrive → Local Web Server...${NC}"
rsync $RSYNC_OPTS --no-p --no-o --no-g "$GDRIVE" "$WEBSERVER"
EXIT1=$?

# 2. PUSH: Push newer local files to cloud
echo -e "\n${CYAN}📤 Pushing: Local Web Server → GDrive...${NC}"
rsync $RSYNC_OPTS --no-p --no-o --no-g "$WEBSERVER" "$GDRIVE"
EXIT2=$?

# ─── STEP 3: FAST TARGETED PERMISSION REPAIR ─────────────────────
# Only applies permissions if the local user is not already owner
echo -e "\n${CYAN}🔧 Verifying Local File Ownership & Permissions...${NC}"

if [ $EXIT1 -eq 0 ] && [ $EXIT2 -eq 0 ]; then
    # Fast path: Ensure the base directory has proper permissions
    chown "$WEB_USER:$WEB_GROUP" "$WEBSERVER"
    chmod 2775 "$WEBSERVER"

    # Only adjust permissions if files deviate from standard (avoids heavy disk/FUSE crawl)
    find "$WEBSERVER" -maxdepth 2 -not -user "$WEB_USER" -exec chown "$WEB_USER:$WEB_GROUP" {} + 2>/dev/null || true
    find "$WEBSERVER" -type d -not -perm 2775 -exec chmod 2775 {} + 2>/dev/null || true
    find "$WEBSERVER" -type f -not -perm 0664 -exec chmod 0664 {} + 2>/dev/null || true

    echo -e "${GREEN}✔ Local permissions maintained ($WEB_USER:$WEB_GROUP).${NC}"
else
    echo -e "${RED}⚠ Sync completed with warnings/errors. Skipping permission changes.${NC}"
fi

# ─── STATUS SUMMARY ───────────────────────────────────────────────
echo -e "\n${YELLOW}==========================================${NC}"
if [ $EXIT1 -eq 0 ] && [ $EXIT2 -eq 0 ]; then
    echo -e "${GREEN}✅ Two-Way Sync Completed in Record Time!${NC}"
else
    echo -e "${RED}❌ Sync experienced errors. Check rclone/FUSE connection.${NC}"
fi
echo -e "${YELLOW}==========================================${NC}"
