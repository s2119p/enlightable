#!/bin/sh

# Capture the exact trigger time (e.g., 2026-06-12 11:56:00 AM)
SHUTDOWN_TIME=$(date "+%Y-%m-%d %I:%M:%S %p")

# 1. Sync files first
echo "💾 Syncing files..."
sync

# 2. Run the 3-second terminal countdown animation
printf "🔌 Shutting down in 3... ⏳\r"
sleep 1
printf "🔌 Shutting down in 2... ⏳\r"
sleep 1
printf "🔌 Shutting down in 1... ⏳\r"
sleep 1

# Move cursor to a new line, print the shutdown time, and say goodbye
printf "\n"
echo "⏰ Triggered at: $SHUTDOWN_TIME"
echo "👋 Goodbye!"

# 3. Create the multi-line message containing the timestamp for your ntfy app
MESSAGE="🌙 Night-time shutdown triggered... 💤
⏰ Time: $SHUTDOWN_TIME
💾 Files synced successfully.
🔌 Powering off. Goodbye!"

# 4. Send it to ntfy using your existing notify.sh script
/srv/scripts/notify.sh "$MESSAGE"

poweroff
