#!/bin/bash

#set -x
set -e

[ -z "@node.bitbucket@" ] && (
	echo "ERROR! The Rundeck node environment variable \"bitbucket\" has not been set."
	exit 1
)
[ -z "@node.opsman-host@" ] && (
	echo "ERROR! The Rundeck node environment variable \"opsman-host\" has not been set."
	exit 1
)
[ -z "@node.opsman-user@" ] && (
	echo "ERROR! The Rundeck node environment variable \"opsman-user\" has not been set."
	exit 1
)
[ -z "@node.pcf-config@" ] && (
	echo "ERROR! The Rundeck node environment variable \"pcf-config\" has not been set."
	exit 1
)
[ -z "@option.opsman-password@" ] && (
	echo "ERROR! The Ops Manager administration UI password needs to be provided."
	exit 1
)

DOWNLOADS_DIR=$HOME/workspace/downloads
SCRIPTS_DIR=$HOME/workspace/scripts
CONFIG_DIR=$HOME/workspace/configs
BACKUP_DIR=$HOME/workspace/backups

if [ "@option.clean@" == "1" ]; then
	rm -fr $DOWNLOADS_DIR
	rm -fr $SCRIPTS_DIR
	rm -fr $CONFIG_DIR
fi

mkdir -p $DOWNLOADS_DIR
mkdir -p $CONFIG_DIR
mkdir -p $BACKUP_DIR

export PATH=$SCRIPTS_DIR:$PATH

if [[ ! -e $SCRIPTS_DIR ]]; then

	curl -v -s -k -L https://@node.bitbucket@/plugins/servlet/archive/projects/CLOUDF/repos/pcf-automation \
		-o $DOWNLOADS_DIR/pcf-automation.zip

	unzip  -o $DOWNLOADS_DIR/pcf-automation.zip -d $SCRIPTS_DIR
fi

curl -v -s -k -L https://@node.bitbucket@/plugins/servlet/archive/projects/CLOUDF/repos/@node.pcf-config@ \
	-o $DOWNLOADS_DIR/@node.pcf-config@.zip

run_job=1
if [[ -e $DOWNLOADS_DIR/@node.pcf-config@.zip.last ]]; then
	set +e
    diff $DOWNLOADS_DIR/@node.pcf-config@.zip $DOWNLOADS_DIR/@node.pcf-config@.zip.last
    if [[ $? -ne 2 ]]; then
        run_job=0
    fi
    set -e
fi

if [[ $run_job -eq 1 ]]; then

    echo "Running Configuration!"

	rm -fr $CONFIG_DIR/@node.pcf-config@
	unzip -o $DOWNLOADS_DIR/@node.pcf-config@.zip -d $CONFIG_DIR/@node.pcf-config@

	cd $CONFIG_DIR/@node.pcf-config@
	if [ -z "@option.opsman-key@" ]; then

		configure-ert -o @node.opsman-host@ \
			-u '@node.opsman-user@' \
			-p '@option.opsman-password@' \
			-w '@option.ldap-bind-password@'
	else
		configure-ert -o @node.opsman-host@ \
			-u '@node.opsman-user@' \
			-p '@option.opsman-password@' \
			-w '@option.ldap-bind-password@' \
			-k '@option.opsman-key@'
	fi

    mv $DOWNLOADS_DIR/@node.pcf-config@.zip $DOWNLOADS_DIR/@node.pcf-config@.zip.last
else
    rm $DOWNLOADS_DIR/@node.pcf-config@.zip
fi

set +e
#set +x