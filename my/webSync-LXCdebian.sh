#!/bin/bash

GDRIVE="/mnt/Moxprox01/webpage/html/"
WEBSERVER="/var/www/html/"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=============================="
echo -e "   Secure HTML Sync Tool      "
echo -e "==============================${NC}"

# ─── STEP 1: PULL — Gdrive → Web Server ───────────────────────────
# We use --no-p --no-o --no-g because GDrive doesn't store Linux owners.
# We use --chmod=Dg=rwx,Fg=rw to ensure files arriving are ready for the web.
echo -e "${CYAN}📥 Pulling: Gdrive → Web Server${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

rsync -rtvzu --progress \
    --chmod=Du=rwx,Dg=rwx,Fu=rw,Fg=rw \
    --no-p --no-o --no-g \
    "$GDRIVE" "$WEBSERVER"

EXIT1=$?

# ─── STEP 2: PUSH — Web Server → Gdrive ───────────────────────────
# When pushing to Gdrive, we ignore permissions to avoid "Operation not permitted" errors
echo -e "\n${CYAN}📤 Pushing: Web Server → Gdrive${NC}"
echo -e "${BLUE}--------------------------------------------------------------${NC}"

rsync -rtvzu --progress \
    --no-p --no-o --no-g \
    "$WEBSERVER" "$GDRIVE"

EXIT2=$?

# ─── FINAL STATUS ─────────────────────────────────────────────────
echo -e "\n${YELLOW}=============================="
if [ $EXIT1 -eq 0 ] && [ $EXIT2 -eq 0 ]; then
    echo -e "${GREEN}✅ Sync Completed Successfully!${NC}"
else
    echo -e "${RED}⚠  Sync Completed with Errors!${NC}"
    echo -e "Check if GDrive mount is connected.${NC}"
fi
echo -e "${YELLOW}==============================${NC}"
