#!/bin/bash

#set -x
set -e

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
# OPSMAN_KEY (optional)
# PCF_CONFIG
# LDAP_BIND_PASSWD (optional)

if [ -z "$DOWNLOADS_DIR" ] ||
    [ -z "$SCRIPTS_DIR" ] ||
    [ -z "$BACKUP_DIR" ] ||
    [ -z "$CONFIG_DIR" ] ||
    [ -z "$OPSMAN_HOST" ] ||
    [ -z "$OPSMAN_USER" ] ||
    [ -z "$OPSMAN_PASSWD" ] ||
    [ -z "$PCF_CONFIG" ]; then

    echo "The required environment variables have not been set."
    exit 1
fi

run_job=1
if [[ -e $DOWNLOADS_DIR/$PCF_CONFIG.zip.last ]]; then
	set +e
    diff $DOWNLOADS_DIR/$PCF_CONFIG.zip $DOWNLOADS_DIR/$PCF_CONFIG.zip.last
    if [[ $? -ne 2 ]]; then
        run_job=0
    fi
    set -e
fi

if [[ $run_job -eq 1 ]]; then

    echo "Running Configuration!"

	rm -fr $CONFIG_DIR/$PCF_CONFIG
	unzip -o $DOWNLOADS_DIR/$PCF_CONFIG.zip -d $CONFIG_DIR/$PCF_CONFIG

	cd $CONFIG_DIR/$PCF_CONFIG
	if [ -z "$OPSMAN_KEY" ]; then

		$SCRIPTS_DIR/configure-ert -o $OPSMAN_HOST \
			-u '$OPSMAN_USER' \
			-p '$OPSMAN_PASSWD' \
			-w '$LDAP_BIND_PASSWD'
	else
		$SCRIPTS_DIR/configure-ert -o $OPSMAN_HOST \
			-u '$OPSMAN_USER' \
			-p '$OPSMAN_PASSWD' \
			-w '$LDAP_BIND_PASSWD' \
			-k '$OPSMAN_KEY'
	fi

    mv $DOWNLOADS_DIR/$PCF_CONFIG.zip $DOWNLOADS_DIR/$PCF_CONFIG.zip.last
else
    rm $DOWNLOADS_DIR/$PCF_CONFIG.zip
fi

set +e
#set +x
