#!/bin/sh -e

if [ ! -e $1 ] ; then
	echo "Usage: $0 dataverse-x.x.war"
	exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "This script requires root privileges. Restarting with sudo..."
    exec sudo "$0" "$@"
fi

sudo -u dataverse /usr/local/payara6/bin/asadmin list-applications | grep dataverse | awk '{ print $1 }' | xargs -i \
	sudo -u dataverse /usr/local/payara6/bin/asadmin undeploy {}

service payara stop

rm -rf /usr/local/payara6/glassfish/domains/domain1/generated/

service payara start

sudo -u dataverse /usr/local/payara6/bin/asadmin deploy $1

service payara stop
service payara start

