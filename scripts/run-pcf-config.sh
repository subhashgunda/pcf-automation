#!/bin/bash

#set -x
set -e

# Environment variables
#
# ROOT_DIR
# CONFIG_DIR
#
# OPSMAN_HOST
# OPSMAN_USER
# OPSMAN_PASSWD
# OPSMAN_KEY (optional)
# TEST_RUN (0/1)
# PCF_CONFIG
# LDAP_BIND_PASSWD (optional)

if [ -z "$ROOT_DIR" ] ||
    [ -z "$CONFIG_DIR" ] ||
    [ -z "$OPSMAN_HOST" ] ||
    [ -z "$OPSMAN_USER" ] ||
    [ -z "$OPSMAN_PASSWD" ] ||
    [ -z "$TEST_RUN" ] ||
    [ -z "$PCF_CONFIG" ]; then

    echo "The required environment variables have not been set."
    exit 1
fi

run_job=1
if [[ ! -e $CONFIG_DIR/$PCF_CONFIG ]]; then
    git clone $CONFIG_GIT_URL --branch master --single-branch $CONFIG_DIR/$PCF_CONFIG
    pushd $CONFIG_DIR/$PCF_CONFIG
    git checkout master
    popd
else
    pushd $CONFIG_DIR/$PCF_CONFIG
    git checkout master

    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    BASE=$(git merge-base @ @{u})

    if [ $LOCAL = $REMOTE ]; then
        run_job=0
    elif [ $LOCAL = $BASE ]; then
        git pull
    else
        echo "Unable to determine state of '$CONFIG_GIT_URL'."
        exit 1
    fi

    popd
fi

test_run=""
if [[ "$TEST_RUN" == "1" ]]; then
    test_run="-t"
fi

if [[ $run_job -eq 1 ]]; then

    echo "Running Configuration!"

	cd $CONFIG_DIR/$PCF_CONFIG
	if [ -z "$OPSMAN_KEY" ]; then

		$ROOT_DIR/scripts/configure-ert.rb -o $OPSMAN_HOST \
			-u "$OPSMAN_USER" \
			-p "$OPSMAN_PASSWD" \
			-w "$LDAP_BIND_PASSWD" \
            $test_run
	else
		$ROOT_DIR/scripts/configure-ert.rb -o $OPSMAN_HOST \
			-u "$OPSMAN_USER" \
			-p "$OPSMAN_PASSWD" \
			-w "$LDAP_BIND_PASSWD" \
			-k "$OPSMAN_KEY" \
            $test_run
	fi

    if [[ "$TEST_RUN" == "1" ]]; then
        # Force config to be re-cloned next run
        rm -fr $CONFIG_DIR/$PCF_CONFIG
    fi
fi

set +e
#set +x
