#!/bin/bash

#set -x

# Environment variables
#
# DOWNLOADS_DIR
# SCRIPTS_DIR
# CONFIG_DIR
# BACKUP_DIR
#
# OPSMAN_HOST
# OPSMAN_USER
# OPSMAN_PASSWD
# OPSMAN_SSH_USER
# OPSMAN_SSH_PASSWORD
# OPSMAN_KEY (optional)
# BACKUP_AGE (optional)

if [ -z "$DOWNLOADS_DIR" ] ||
    [ -z "$SCRIPTS_DIR" ] ||
    [ -z "$BACKUP_DIR" ] ||
    [ -z "$CONFIG_DIR" ] ||
    [ -z "$OPSMAN_HOST" ] ||
    [ -z "$OPSMAN_USER" ] ||
    [ -z "$OPSMAN_SSH_USER" ] ||
    [ -z "$OPSMAN_SSH_PASSWORD" ]; then

    echo "The required environment variables have not been set."
    exit 1
fi

case $(uname) in
    Linux)
        cd $SCRIPTS_DIR/tools/linux
        ;;
    Darwin)
        cd $SCRIPTS_DIR/tools/darwin
        ;;
    *)
        echo "ERROR: Unable to identify OS type."
        exit 1
esac

if [ -n "$OPSMAN_KEY" ]; then
    ENCRYPTION_OPTION="--encryptionkey '$OPSMAN_KEY'"
fi

tiles=(
    ops-manager
    elastic-runtime
    mysql-tile
# 	redis-tile
# 	rabbitmq
)

BACKUP_TIMESTAMP_DIR=$BACKUP_DIR/$(date +%Y%m%d%H%M%S)
mkdir -p $BACKUP_TIMESTAMP_DIR

export LOG_LEVEL=debug

for t in ${tiles[*]}; do

    echo -e "\n**** Backing up tile '$t' ****\n"

    echo -e "\n\n==> Backup logs for tile '$t': \n" >> $BACKUP_TIMESTAMP_DIR.log

    ./cfops backup $ENCRYPTION_OPTION \
        --opsmanagerhost "$OPSMAN_HOST" \
        --adminuser "$OPSMAN_USER" \
        --adminpass "$OPSMAN_PASSWD" \
        --opsmanageruser "$OPSMAN_SSH_USER" \
        --opsmanagerpass "$OPSMAN_SSH_PASSWORD" \
        --tile $t \
        --destination $BACKUP_TIMESTAMP_DIR 2>&1 | tee -a $BACKUP_TIMESTAMP_DIR.log

    if [[ $? -ne 0 ]]; then
        rm -fr $BACKUP_TIMESTAMP_DIR
        echo "ERROR! Backup of tile '$t' failed."
        exit 1
    fi
done

# Delete old backup files. By default
# only the most recent backup is kept

if [ -n "$BACKUP_AGE" ]; then
    BACKUP_AGE=0
fi
find $BACKUP_DIR -mtime +$BACKUP_AGE -delete

#set +x
