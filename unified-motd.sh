#!/bin/sh
# Centralized, Self-Updating, POSIX-Compliant Unified MOTD
# Works on Alpine, Mint, Armbian, Proxmox Host, and LXC containers.

# --- Configuration ---
# CHANGE THIS to your raw GitHub URL so the script can update itself
GITHUB_URL="https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/unified-motd.sh"
SCRIPT_PATH="/etc/profile.d/99-unified-motd.sh"

# --- ANSI Colors ---
RESET="\033[0m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
MAGENTA="\033[1;35m"

# --- Auto-Detect OS & Architecture ---
ARCH=$(uname -m)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME
    OS_ID=$ID
else
    OS_NAME=$(uname -s)
    OS_ID="unknown"
fi

# --- Auto-Detect Environment (Host vs LXC) ---
if [ -d /etc/pve ]; then
    SCOPE="Proxmox Host"
elif [ -f /run/systemd/container ] || [ -d /proc/vz ] || { [ -f /sbin/init ] && grep -q "lxc" /proc/1/environ 2>/dev/null; }; then
    SCOPE="LXC Container"
else
    SCOPE="Bare-Metal / VM"
fi

# --- Dynamic Metrics Extraction ---
HOSTNAME=$(hostname)
USERS=$(who | wc -l 2>/dev/null || echo "1")
UPTIME=$(uptime | awk -F'(up |,| load)' '{print $2}' | sed 's/^[ \t]*//')
LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1", "$2", "$3}' || echo "N/A")

# Portable Memory Extraction
RAM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/ || /Mem/ {print $2}')
RAM_USED=$(free -m 2>/dev/null | awk '/Mem:/ || /Mem/ {print $3}')
if [ -n "$RAM_TOTAL" ] && [ "$RAM_TOTAL" -gt 0 ]; then
    RAM_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
else
    RAM_PCT=0
    RAM_TOTAL=0
    RAM_USED=0
fi

# Portable Disk extraction
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_PCT=$(df -h / | awk 'NR==2 {print $5}')

# Portable IP detection
IP_ADDR=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
[ -z "$IP_ADDR" ] && IP_ADDR=$(hostname -i 2>/dev/null | awk '{print $1}')

# CPU Temperature Fallback
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    CPU_TEMP="$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))°C"
else
    CPU_TEMP="N/A"
fi

# --- Print the MOTD Dashboard ---
clear
echo -e "${CYAN}  _   _ _   _ ___ _____ ___ ___ ___ "
echo -e " | | | | \ | |_ _|  ___|_ _| __|   \\"
echo -e " | |_| |  \| || || |_   | || _|| |) |"
echo -e "  \___/|_| \_|___|_|   |___|___|___/ ${RESET}"
echo -e ""
echo -e "${YELLOW}================= SYSTEM SPECIFICATIONS =================${RESET}"
printf " ${GREEN}- Hostname:${RESET}   %-16s ${GREEN}- OS/Distro:${RESET}  %s (%s)\n" "$HOSTNAME" "$OS_NAME" "$ARCH"
printf " ${GREEN}- Scope:${RESET}      %-16s ${GREEN}- IP Address:${RESET} %s\n" "$SCOPE" "$IP_ADDR"
if [ "$SCOPE" = "Proxmox Host" ]; then
    printf " ${GREEN}- Web GUI:${RESET}    https://%s:8006\n" "$IP_ADDR"
fi
echo -e ""
echo -e "${YELLOW}=================== LIVE SYSTEM STATS ===================${RESET}"
printf " ${GREEN}- System Load:${RESET} %-15s ${GREEN}- System Uptime:${RESET} %s\n" "$LOAD" "$UPTIME"
printf " ${GREEN}- RAM Usage:${RESET}   %dMB / %dMB (%d%%) ${GREEN}- Disk (Root /):${RESET} %s of %s\n" "$RAM_USED" "$RAM_TOTAL" "$RAM_PCT" "$DISK_PCT" "$DISK_TOTAL"
printf " ${GREEN}- CPU Temp:${RESET}    %-16s ${GREEN}- Active Users:${RESET}  %d\n" "$CPU_TEMP" "$USERS"
echo -e ""
echo -e "${YELLOW}================== QUICK CHEAT SHEETS ===================${RESET}"
if [ "$OS_ID" = "alpine" ]; then
    echo -e " ${BLUE}* Alpine Command:${RESET} \"apk add <package>\" or \"apk update\""
else
    echo -e " ${BLUE}* Debian Command:${RESET} \"apt update && apt upgrade\""
fi
if [ "$SCOPE" = "Proxmox Host" ]; then
    echo -e " ${BLUE}* Proxmox CLI:${RESET}    \"pct list\" (Containers) | \"qm list\" (VMs)"
fi
echo -e " ${MAGENTA}* Forums:${RESET}         https://wiki.alpinelinux.org | https://forum.proxmox.com"
echo -e "${YELLOW}=========================================================${RESET}"

# --- Self-Updating Logic (Background execution) ---
# Only attempts update if the current user has write access to the script path
if [ -w "$SCRIPT_PATH" ]; then
    # Checks if the file is older than 24 hours (1440 minutes)
    if [ -n "$(find "$SCRIPT_PATH" -mmin +1440 2>/dev/null)" ]; then
        (
            TEMP_FILE="${SCRIPT_PATH}.tmp"
            if command -v curl >/dev/null 2>&1; then
                curl -s --connect-timeout 2 "$GITHUB_URL" > "$TEMP_FILE" 2>/dev/null
            elif command -v wget >/dev/null 2>&1; then
                wget -q -T 2 -O "$TEMP_FILE" "$GITHUB_URL" 2>/dev/null
            fi
            
            # Verify download was successful, swap, and clean up
            if [ -s "$TEMP_FILE" ]; then
                mv "$TEMP_FILE" "$SCRIPT_PATH"
                chmod +x "$SCRIPT_PATH"
            else
                rm -f "$TEMP_FILE"
            fi
        ) &
    fi
fi
