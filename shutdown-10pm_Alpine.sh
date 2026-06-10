#!/bin/sh
#!/bin/sh
/srv/scripts/notify.sh "It's 10:00pm shutdown now..."
sync && sleep 2
/sbin/poweroff