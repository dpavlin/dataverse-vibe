#!/bin/sh -e

if [ ! -e $1 ] ; then
	echo "Usage: $0 dataverse-x.x.war"
	exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Restarting with sudo..."
    exec sudo "$0" "$@"
fi

# Start tailing logs in background
tail -f /usr/local/payara6/glassfish/domains/domain1/logs/*.log &
TAIL_PID=$!
echo "Log tailing started in background (PID: $TAIL_PID)"

# Set up trap to kill the tail process when the script exits
trap "kill $TAIL_PID 2>/dev/null || true; echo 'Log tailing stopped'" EXIT INT TERM

sudo -u dataverse /usr/local/payara6/bin/asadmin list-applications | grep dataverse | awk '{ print $1 }' | xargs -i \
	sudo -u dataverse /usr/local/payara6/bin/asadmin undeploy {}

service payara stop

rm -rf /usr/local/payara6/glassfish/domains/domain1/generated/

service payara start

sudo -u dataverse /usr/local/payara6/bin/asadmin deploy $1

service payara stop
service payara start

