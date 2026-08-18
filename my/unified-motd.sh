#!/bin/sh
# ==============================================================================
# Pure POSIX Lightweight MOTD with Classic Tux (Zero Dependencies)
# ==============================================================================

# ANSI Color Codes
RESET='\033[0m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
DARK='\033[1;30m'
GRAY='\033[0;37m'

# 1. System Information Gathering
HOSTNAME=$(hostname)
KERNEL=$(uname -r)
ARCH=$(uname -m)

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="${PRETTY_NAME:-$NAME}"
else
    OS_NAME="$(uname -s) $(uname -r)"
fi

# 2. Network IP & Interface
NET_IF=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
IP_ADDR=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
[ -z "$IP_ADDR" ] && IP_ADDR=$(ip -4 addr show | awk '/inet / {print $2}' | cut -d/ -f1 | grep -v '^127\.' | xargs)

# 3. Uptime & Boot Time
UPTIME_SEC=$(cut -d. -f1 /proc/uptime)
DAYS=$(( UPTIME_SEC / 86400 ))
HOURS=$(( (UPTIME_SEC % 86400) / 3600 ))
MINS=$(( (UPTIME_SEC % 3600) / 60 ))

if [ "$DAYS" -gt 0 ]; then
    UPTIME_STR="${DAYS}d ${HOURS}h ${MINS}m"
else
    UPTIME_STR="${HOURS}h ${MINS}m"
fi

NOW_SEC=$(date +%s)
BOOT_SEC=$(( NOW_SEC - UPTIME_SEC ))
BOOT_TIME=$(date -d "@$BOOT_SEC" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$BOOT_SEC" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "N/A")

# 4. CPU & Load
CPU_CORES=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo "1")
LOAD=$(uptime | awk -F'load average:' '{print $2}' | xargs)

if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then
    FREQ_RAW=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)
    GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "")
    CPU_FREQ="$(( FREQ_RAW / 1000 )) MHz ${GOV:+($GOV)}"
else
    CPU_FREQ="N/A"
fi

# 5. Temperature Detection
CPU_TEMP="N/A"
for temp_file in \
    /sys/class/thermal/thermal_zone0/temp \
    /sys/class/hwmon/hwmon0/temp1_input \
    /sys/class/hwmon/hwmon1/temp1_input; do
    if [ -f "$temp_file" ]; then
        T_RAW=$(cat "$temp_file" 2>/dev/null)
        if [ -n "$T_RAW" ] && [ "$T_RAW" -gt 0 ]; then
            CPU_TEMP="$(( T_RAW / 1000 ))°C"
            break
        fi
    fi
done

# 6. Memory Usage
MEM_TOTAL_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
MEM_AVAIL_KB=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
if [ -n "$MEM_TOTAL_KB" ] && [ -n "$MEM_AVAIL_KB" ]; then
    MEM_USED_KB=$(( MEM_TOTAL_KB - MEM_AVAIL_KB ))
    MEM_TOTAL_MB=$(( MEM_TOTAL_KB / 1024 ))
    MEM_USED_MB=$(( MEM_USED_KB / 1024 ))
    MEM_PERC=$(( MEM_USED_KB * 100 / MEM_TOTAL_KB ))
else
    MEM_TOTAL_MB="N/A"; MEM_USED_MB="N/A"; MEM_PERC="N/A"
fi

# 7. Swap Usage
SWAP_TOTAL_KB=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
SWAP_FREE_KB=$(awk '/SwapFree:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
if [ -n "$SWAP_TOTAL_KB" ] && [ "$SWAP_TOTAL_KB" -gt 0 ]; then
    SWAP_USED_MB=$(( (SWAP_TOTAL_KB - SWAP_FREE_KB) / 1024 ))
    SWAP_TOTAL_MB=$(( SWAP_TOTAL_KB / 1024 ))
    SWAP_INFO="${SWAP_USED_MB}MB / ${SWAP_TOTAL_MB}MB"
else
    SWAP_INFO="Disabled"
fi

# 8. Disk Usage
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_PERC=$(df -h / | awk 'NR==2 {print $5}')

# 9. Active Users
USERS_COUNT=$(who 2>/dev/null | wc -l | xargs)

# ==============================================================================
# Display Header: Tux Penguin (Left) + Primary Host Info (Right)
# ==============================================================================
printf "${WHITE}   .--.       ${WHITE}%s${RESET}\n" "$HOSTNAME"
printf "${WHITE}  |${WHITE}o${DARK}_${WHITE}o ${WHITE}|      ${CYAN}OS:${RESET} %s (%s)\n" "$OS_NAME" "$ARCH"
printf "${WHITE}  |${YELLOW}:_/${WHITE} |      ${CYAN}Kernel:${RESET} %s\n" "$KERNEL"
printf "${WHITE} //   \\ \\     ${CYAN}IP:${RESET} %s (%s)\n" "$IP_ADDR" "${NET_IF:-eth0}"
printf "${WHITE}(|     | )${RESET}\n"
printf "${YELLOW}/'\\${WHITE}_   _${YELLOW}/'\`\\${RESET}\n"
printf "${YELLOW}\\___)=(___/${RESET}\n"

# ==============================================================================
# Display System Status Block
# ==============================================================================
printf "${GRAY}--------------------------------------------------${RESET}\n"
printf " ${WHITE}System Status:${RESET}\n"
printf "   ${CYAN}CPU Info:${RESET}     %s Cores @ %s\n" "$CPU_CORES" "$CPU_FREQ"
printf "   ${CYAN}CPU Temp:${RESET}     %s\n" "$CPU_TEMP"
printf "   ${CYAN}Uptime:${RESET}       %s (Booted: %s)\n" "$UPTIME_STR" "$BOOT_TIME"
printf "   ${CYAN}Load Average:${RESET} %s\n" "$LOAD"
printf "   ${CYAN}Memory Usage:${RESET} %sMB / %sMB (%s%%)\n" "$MEM_USED_MB" "$MEM_TOTAL_MB" "$MEM_PERC"
printf "   ${CYAN}Swap Usage:${RESET}   %s\n" "$SWAP_INFO"
printf "   ${CYAN}Disk Usage:${RESET}   %s / %s (%s)\n" "$DISK_USED" "$DISK_TOTAL" "$DISK_PERC"
printf "   ${CYAN}Active Users:${RESET} %s session(s)\n" "$USERS_COUNT"
printf "${GRAY}--------------------------------------------------${RESET}\n\n"
