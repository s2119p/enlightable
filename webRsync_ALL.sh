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

echo -e "${YELLOW}=========================================="
echo -e "     Universal Secure HTML Sync Tool      "
echo -e "==========================================${NC}"

# ─── STEP 0: SYSTEM AUTO-DETECTION ───────────────────────────────
echo -e "${CYAN}🔍 Detecting System Environment...${NC}"

# 1. Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_ID="$ID"
else
    OS_NAME="Unknown Linux"
    OS_ID="unknown"
fi

# 2. Detect Architecture
ARCH=$(uname -m)

# 3. Detect if running on TV Box / Hardware Platform
IS_TVBOX=false
if [ -f /sys/firmware/devicetree/base/model ] && grep -qi -E "mxq|s905|amlogic|allwinner|rockchip" /sys/firmware/devicetree/base/model; then
    IS_TVBOX=true
elif grep -qi -E "mxq|tvbox|amlogic" /proc/cpuinfo 2>/dev/null; then
    IS_TVBOX=true
elif [[ "$HOSTNAME" =~ "mxq" || "$HOSTNAME" =~ "tvbox" ]]; then
    IS_TVBOX=true
fi

# 4. Resolve Web User and Group dynamically
# - Standard Alpine LXC: uses 'sudhir:apache' if user 'sudhir' exists
# - Alpine TV Box / Debian: uses 'www-data:www-data' or falls back to 'apache:apache'
if [ "$OS_ID" = "alpine" ] && [ "$IS_TVBOX" = "false" ] && id "sudhir" &>/dev/null; then
    WEB_USER="sudhir"
    WEB_GROUP="apache"
elif id "www-data" &>/dev/null; then
    WEB_USER="www-data"
    WEB_GROUP="www-data"
elif id "apache" &>/dev/null; then
    WEB_USER="apache"
    WEB_GROUP="apache"
else
    WEB_USER="root"
    WEB_GROUP="root"
fi

# 5. Set Optimal Rsync Flags
# TV Box uses checksums (-c) to verify file integrity on flash memory/SD cards.
RSYNC_FLAGS="-rtvzu"
if [ "$IS_TVBOX" = "true" ]; then
    RSYNC_FLAGS="-rtvzuc"
fi

# Print Auto-Detection Results
echo -e "   OS Detected  : ${GREEN}$OS_NAME ($ARCH)${NC}"
echo -e "   Platform     : ${GREEN}$( [ "$IS_TVBOX" = "true" ] && echo "Alpine TV Box Edition (Checksum Enabled)" || echo "Standard Container/Server" )${NC}"
echo -e "   Web User     : ${GREEN}$WEB_USER${NC}"
echo -e "   Web Group    : ${GREEN}$WEB_GROUP${NC}"
echo -e "   Rsync Flags  : ${GREEN}$RSYNC_FLAGS${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

# ─── STEP 1: PRE-FLIGHT ENVIRONMENT CHECKS ───────────────────────
# Create local webserver directory if missing
if [ ! -d "$WEBSERVER" ]; then
    echo -e "${YELLOW}Directory $WEBSERVER not found. Creating...${NC}"
    mkdir -p "$WEBSERVER"
fi

# Verify Gdrive is actually mounted (prevents filling up local disk storage)
if ! mountpoint -q "/mnt/Moxprox01"; then
    echo -e "${RED}❌ ERROR: Gdrive mount point /mnt/Moxprox01 is NOT active!${NC}"
    echo -e "${RED}Sync aborted to prevent local disk overflow.${NC}"
    exit 1
fi

# Create Gdrive directory if missing
if [ ! -d "$GDRIVE" ]; then
    echo -e "${YELLOW}Gdrive directory $GDRIVE not found. Creating...${NC}"
    mkdir -p "$GDRIVE"
fi

# ─── STEP 2: PULL — Gdrive → Web Server ───────────────────────────
echo -e "\n${CYAN}📥 Pulling: Gdrive → Web Server${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

rsync $RSYNC_FLAGS --progress \
    --no-p --no-o --no-g \
    "$GDRIVE" "$WEBSERVER"

EXIT1=$?

# ─── STEP 3: SELF-HEALING & PERMISSION HARDENING ─────────────────
echo -e "\n${CYAN}🔧 Applying Unified Permissions...${NC}"

if [ $EXIT1 -eq 0 ]; then
    # 1. Reset ownership to the determined user and web group
    chown -R "$WEB_USER:$WEB_GROUP" "$WEBSERVER"

    # 2. Secure Directory Permissions (Setgid 2775 so new files inherit the group)
    find "$WEBSERVER" -type d -exec chmod 2775 {} +

    # 3. Secure File Permissions (0664)
    find "$WEBSERVER" -type f -exec chmod 0664 {} +

    # 4. Custom security hardening for sensitive configurations (if they exist)
    if [ -f "$WEBSERVER/my-notes/index.php" ]; then
        chmod 644 "$WEBSERVER/my-notes/index.php"
    fi
    if [ -f "$WEBSERVER/my-notes/.htaccess" ]; then
        chmod 644 "$WEBSERVER/my-notes/.htaccess"
    fi

    echo -e "${GREEN}✔ Permissions Unified: Directories(2775), Files(0664)${NC}"
else
    echo -e "${RED}❌ Pull failed. Skipping permission hardening step.${NC}"
fi

# ─── STEP 4: PUSH — Web Server → Gdrive ───────────────────────────
echo -e "\n${CYAN}📤 Pushing: Web Server → Gdrive${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

rsync $RSYNC_FLAGS --progress \
    --no-p --no-o --no-g \
    "$WEBSERVER" "$GDRIVE"

EXIT2=$?

# ─── FINAL STATUS ─────────────────────────────────────────────────
echo -e "\n${YELLOW}=========================================="
if [ $EXIT1 -eq 0 ] && [ $EXIT2 -eq 0 ]; then
    echo -e "${GREEN}✅ Sync & Hardening Completed Successfully!${NC}"
else
    echo -e "${RED}⚠  Sync Completed with Errors!${NC}"
    echo -e "Please verify your network mount and disk health.${NC}"
fi
echo -e "${YELLOW}==========================================${NC}"
