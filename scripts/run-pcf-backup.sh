#!/bin/bash

#set -x

# Environment variables
#
# ROOT_DIR
# BACKUP_DIR
#
# OPSMAN_HOST
# OPSMAN_USER
# OPSMAN_PASSWD
# OPSMAN_SSH_USER
# OPSMAN_SSH_PASSWORD
# OPSMAN_KEY (optional)
# BACKUP_AGE (optional)

if [ -z "$ROOT_DIR" ] ||
    [ -z "$BACKUP_DIR" ] ||
    [ -z "$OPSMAN_HOST" ] ||
    [ -z "$OPSMAN_USER" ] ||
    [ -z "$OPSMAN_SSH_USER" ] ||
    [ -z "$OPSMAN_SSH_PASSWORD" ]; then

    echo "The required environment variables have not been set."
    exit 1
fi

source $ROOT_DIR/scripts/common.sh
cd $TOOLS_DIR

if [ -n "$OPSMAN_KEY" ]; then
    ENCRYPTION_OPTION="--encryptionkey '$OPSMAN_KEY'"
fi

tiles=(
    ops-manager
    elastic-runtime
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

if [[ -n "$BACKUP_DIR" ]] && [[ "$BACKUP_DIR" != "/" ]]; then
    if [[ -z "$BACKUP_AGE" ]]; then
        BACKUP_AGE=0
    fi

    # Delete backup directories recursively using directory timestamp
    for d in $(find $BACKUP_DIR -mtime +$BACKUP_AGE -type d -links 2 -print); do 
        if [[ -z $(echo $d | grep 'mysql-service$') ]]; then 
            echo "Deleting old backup: $d";
            rm -fr $d 
        fi
    done
    find $BACKUP_DIR/*.log -mtime +$BACKUP_AGE -type f -delete

    # Delete old log files and backup dir names older than given age
    BACKUP_DIR_TO_DELETE=$(date +%Y%m%d%H%M%S -d "$BACKUP_AGE day ago")
    echo "Deleting backup dirs and logs older than $BACKUP_DIR_TO_DELETE..."

    for f in $BACKUP_DIR/*; do
        if [[ -z $(echo $f | grep 'mysql-service$') ]]; then
            filename=$(basename $f)
            name="${filename%.*}"
            if [[ $name -lt $BACKUP_DIR_TO_DELETE ]]; then
                echo "Deleting: $d";
                rm -fr $f
            fi
        fi
    done
fi

#set +x
