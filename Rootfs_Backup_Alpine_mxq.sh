#!/bin/sh

# Set the destination (Current folder or external drive)
# To save to a USB, change this to /media/usb_name
DEST="/"
DATE=$(date +%Y-%m-%d_%H-%M)
HOSTNAME=$(hostname)
FILENAME="$DEST/${HOSTNAME}_Alpine_backup_$DATE.tar.gz"

echo "--- Starting Backup: $FILENAME ---"

# 1. Create a temporary exclude file
EXCLUDES="/tmp/backup_excludes.txt"
cat <<EOF > $EXCLUDES
boot/*
proc/*
sys/*
dev/*
run/*
tmp/*
var/cache/*
var/tmp/*
mnt/*
media/*
lost+found
root/*.tar.gz
EOF

# 2. Perform the backup
# We use -C / to ensure we are at root level
tar -cvpzf "$FILENAME" -X "$EXCLUDES" -C / .

# 3. Cleanup
rm "$EXCLUDES"

echo "------------------------------------------"
echo "Backup Complete!"
echo "Size: $(du -sh $FILENAME | awk '{print $1}')"
echo "Location: $FILENAME"
echo "Reminder: Download this to your PC and delete it from the box."