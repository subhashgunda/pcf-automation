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
[ -z "@node.opsman-ssh-user@" ] && (
	echo "ERROR! The Rundeck node environment variable \".opsman-ssh-user\" has not been set."
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

case $(uname) in
	Linux)
		cd $HOME/workspace/scripts/tools/linux
		;;
	Darwin)
		cd $HOME/workspace/scripts/tools/darwin
		;;
	*)
		echo "ERROR: Unable to identify OS type."
		exit 1
esac

if [ -n "@option.opsman-user@" ]; then
	ENCRYPTION_OPTION="--encryptionkey '@option.opsman-user@'"
fi

tiles=(
	ops-manager
	elastic-runtime
 	mysql-tile
# 	redis-tile
# 	rabbitmq
)

set +e

BACKUP_TIMESTAMP_DIR=$BACKUP_DIR/$(date +%Y%m%d%H%M%S)
mkdir -p $BACKUP_TIMESTAMP_DIR

export LOG_LEVEL=debug

for t in ${tiles[*]}; do

	echo -e "\n**** Backing up tile '$t' ****\n"

	echo -e "\n\n==> Backup logs for tile '$t': \n" >> $BACKUP_TIMESTAMP_DIR.log

	./cfops backup $ENCRYPTION_OPTION \
		--opsmanagerhost '@node.opsman-host@' \
		--adminuser '@node.opsman-user@' \
		--adminpass '@option.opsman-password@' \
		--opsmanageruser '@node.opsman-ssh-user@' \
		--opsmanagerpass '@option.opsman-ssh-password@' \
		--tile $t \
		--destination $BACKUP_TIMESTAMP_DIR 2>&1 | tee -a $BACKUP_TIMESTAMP_DIR.log

	if [[ $? -ne 0 ]]; then
		rm -fr $BACKUP_TIMESTAMP_DIR
		echo "ERROR! Backup of tile '$t' failed."
	fi
done

# Delete old backup files. By default
# only the most recent backup is kept

BACKUP_AGE="@option.backup-age@"
if [ -n "$BACKUP_AGE" ]; then
	BACKUP_AGE=0
fi
find $BACKUP_DIR -mtime +$BACKUP_AGE -delete

set +x
