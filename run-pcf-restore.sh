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
# TIMESTAMP

if [ -z "$DOWNLOADS_DIR" ] ||
    [ -z "$SCRIPTS_DIR" ] ||
    [ -z "$CONFIG_DIR" ] ||
    [ -z "$OPSMAN_HOST" ] ||
    [ -z "$OPSMAN_USER" ] ||
    [ -z "$OPSMAN_SSH_USER" ] ||
    [ -z "$OPSMAN_SSH_PASSWORD" ] ||
    [ -z "$TIMESTAMP" ]; then

    echo -n "The required environment variables have not been set."
    exit 1
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

if [ -n "$OPSMAN_KEY" ]; then
    ENCRYPTION_OPTION="--encryptionkey '$OPSMAN_KEY'"
fi

tiles=(
#    ops-manager
    elastic-runtime
    mysql-tile
# 	redis-tile
# 	rabbitmq
)

BACKUP_TIMESTAMP_DIR=$BACKUP_DIR/$TIMESTAMP
INSTALLATION_ZIP=$BACKUP_TIMESTAMP_DIR/opsmanager/installation.zip

if [ -z "$TIMESTAMP" ] || [ ! -e "$INSTALLATION_ZIP" ]; then
    echo "ERROR! "$BACKUP_TIMESTAMP_DIR" is not a backup directory."
    exit 1
fi

export LOG_LEVEL=debug

for t in ${tiles[*]}; do

    echo -e "\n**** Restoring tile '$t' ****\n"

    echo -e "\n\n==> Restore logs for tile '$t': \n" >> $RESTORE_TIMESTAMP_DIR.log

    ./cfops restore $ENCRYPTION_OPTION \
        --opsmanagerhost "$OPSMAN_HOST" \
        --adminuser "$OPSMAN_USER" \
        --adminpass "$OPSMAN_PASSWD" \
        --opsmanageruser "$OPSMAN_SSH_USER" \
        --opsmanagerpass "$OPSMAN_SSH_PASSWORD" \
        --tile $t \
        --destination $BACKUP_TIMESTAMP_DIR 2>&1 | tee -a $RESTORE_TIMESTAMP_DIR.log

    if [[ $? -ne 0 ]]; then
        echo "ERROR! Restore of tile '$t' failed."
        exit 1
    fi
done

#set +x
