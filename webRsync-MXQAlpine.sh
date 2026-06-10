#!/bin/bash

# ─── CONFIGURATION ───────────────────────────────────────────────
# Source: Your GDrive mount
GDRIVE="/mnt/Moxprox01/webpage/html/"
# Destination: web root (Updated from /var/www/html)
WEBSERVER="/var/www/html/"
# User: Your local user
WEB_USER="www-data"
# Group: Debian/Armbian standard web group (Updated from apache)
WEB_GROUP="www-data"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=============================="
echo -e "   TVBOX Secure Sync Tool    "
echo -e "   Alpine TVBOX Edition     "
echo -e "==============================${NC}"

# ─── STEP 0: ENVIRONMENT CHECK ──────────────────────────────────
echo -e "${CYAN}🔍 Checking environment...${NC}"

# Create Webserver directory if missing
if [ ! -d "$WEBSERVER" ]; then
    echo -e "${YELLOW}Directory $WEBSERVER not found. Creating...${NC}"
    mkdir -p "$WEBSERVER"
fi

# Verify Gdrive is actually mounted (Prevents filling up local disk)
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

# ─── STEP 1: PULL — Gdrive → Web Server ───────────────────────────
echo -e "\n${CYAN}📥 Pulling: Gdrive → Web Server${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

# -rtvzuc: Recursive, Times, Verbose, Compress, Update, Checksum
# --no-p --no-o --no-g: GDrive/FUSE doesn't support Linux permissions, 
# so we strip them during sync and apply them locally in Step 2.
rsync -rtvzuc --progress \
    --no-p --no-o --no-g \
    "$GDRIVE" "$WEBSERVER"

EXIT1=$?

# ─── STEP 2: SELF-HEALING PERMISSIONS ────────────────────────────
echo -e "\n${CYAN}🔧 Applying Self-Healing Permissions...${NC}"

if [ $EXIT1 -eq 0 ]; then
    # 1. Reset ownership to your user and the web group (www-data)
    chown -R "$WEB_USER:$WEB_GROUP" "$WEBSERVER"

    # 2. Fix Directories: 2775 
    # The '2' (SETGID) ensures new files created in these folders inherit the 'www-data' group.
    find "$WEBSERVER" -type d -exec chmod 2775 {} +

    # 3. Fix Files: 0664
    # Ensures the web server can read and the user/group can write.
    find "$WEBSERVER" -type f -exec chmod 0664 {} +

    echo -e "${GREEN}✔ Permissions Unified: Directories(2775), Files(0664)${NC}"
else
    echo -e "${RED}❌ Pull failed. Skipping permission hardening.${NC}"
fi

# ─── STEP 3: PUSH — Web Server → Gdrive ───────────────────────────
echo -e "\n${CYAN}📤 Pushing: Web Server → Gdrive${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

rsync -rtvzuc --progress \
    --no-p --no-o --no-g \
    "$WEBSERVER" "$GDRIVE"

EXIT2=$?

# ─── FINAL STATUS ─────────────────────────────────────────────────
echo -e "\n${YELLOW}=============================="
if [ $EXIT1 -eq 0 ] && [ $EXIT2 -eq 0 ]; then
    echo -e "${GREEN}✅ Sync Completed Successfully!${NC}"
else
    echo -e "${RED}⚠  Sync Completed with Errors!${NC}"
    echo -e "Check if GDrive mount is active or if there are disk space issues."
fi
echo -e "${YELLOW}==============================${NC}"