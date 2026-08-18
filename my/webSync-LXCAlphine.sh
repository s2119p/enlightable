#!/bin/bash

# ─── CONFIGURATION ───────────────────────────────────────────────
GDRIVE="/mnt/Moxprox01/webpage/html/"
WEBSERVER="/var/www/html/"
WEB_USER="sudhir"
WEB_GROUP="apache"  # Changed from www-data to apache for Alpine

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=============================="
echo -e "   Alpine Secure Sync Tool    "
echo -e "==============================${NC}"

# ─── STEP 1: PULL — Gdrive → Web Server ───────────────────────────
echo -e "${CYAN}📥 Pulling: Gdrive → Web Server${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

# --chmod: D2775 = Folders get Setgid (s) bit, F664 = Files get rw-rw-r--
rsync -rtvzu --progress \
    --chmod=D2775,F664 \
    --no-p --no-o --no-g \
    "$GDRIVE" "$WEBSERVER"

EXIT1=$?

# ─── STEP 2: FIXING PERMISSIONS AUTOMATICALLY ────────────────────
# This section makes sure that even if rsync missed something, 
# the web server can always read/write the notes.
echo -e "\n${CYAN}🔧 Hardening Permissions...${NC}"

# 1. Claim ownership (sudhir owns, apache group can write)
chown -R $WEB_USER:$WEB_GROUP "$WEBSERVER"

# 2. Ensure all folders have Setgid (Inherit group)
find "$WEBSERVER" -type d -exec chmod 2775 {} +

# 3. Ensure code files are Read-Only for the web process (Security)
if [ -f "$WEBSERVER/my-notes/index.php" ]; then
    chmod 644 "$WEBSERVER/my-notes/index.php"
fi
if [ -f "$WEBSERVER/my-notes/.htaccess" ]; then
    chmod 644 "$WEBSERVER/my-notes/.htaccess"
fi

echo -e "${GREEN}✔ Local Permissions set to Secure Foundation.${NC}"

# ─── STEP 3: PUSH — Web Server → Gdrive ───────────────────────────
echo -e "\n${CYAN}📤 Pushing: Web Server → Gdrive${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

rsync -rtvzu --progress \
    --no-p --no-o --no-g \
    "$WEBSERVER" "$GDRIVE"

EXIT2=$?

# ─── FINAL STATUS ─────────────────────────────────────────────────
echo -e "\n${YELLOW}=============================="
if [ $EXIT1 -eq 0 ] && [ $EXIT2 -eq 0 ]; then
    echo -e "${GREEN}✅ Sync & Hardening Completed Successfully!${NC}"
else
    echo -e "${RED}⚠  Sync Completed with Errors!${NC}"
    echo -e "Check if GDrive mount /mnt/Moxprox01 is active.${NC}"
fi
echo -e "${YELLOW}==============================${NC}"
