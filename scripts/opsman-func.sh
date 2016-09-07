#!/bin/bash

if [[ -z $ROOT_DIR ]]; then
    ROOT_DIR=$(cd $(dirname $0)/.. && pwd)
fi
if [[ -z $TOOLS_DIR ]]; then
    source $ROOT_DIR/scripts/common.sh
fi

function opsman::set_uaac_cli() {
    which uaac 2>&1 > /dev/null
    if [ $? -ne 0 ]; then
        which bundle 2>&1 > /dev/null
        if [ $? -ne 0 ]; then
            echo "ERROR! Unable to find uaac cli."
            exit 1
        fi
        export BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/uaac/Gemfile 
        uaac="bundle exec uaac"
    else
        uaac="uaac"
    fi
}

function opsman::login() {

    opsman::set_uaac_cli

    local opsman_host=$1
    local opsman_user=$2
    local opsman_passwd=$3

    OPSMAN_URL=https://$opsman_host

    $uaac target https://$opsman_host/uaa --skip-ssl-validation
    $uaac token owner get opsman $opsman_user -s '' -p $opsman_passwd

    opsman_token=$($uaac context | awk '/access_token:/{ print $2 }')
}

function opsman::get_installation() {
    
    curl -k $OPSMAN_URL/api/installation_settings \
        -X GET -H "Authorization: Bearer $opsman_token" 2> /dev/null
}

function opsman::get_director_ip() {

    opsman::get_installation | $TOOLS_DIR/jq \
        '.ip_assignments.assignments | with_entries(select(.key|match("p-bosh-.*"))) | to_entries[0].value | to_entries[0].value | to_entries[0].value[0]' | \
        sed 's|"||g'
}

function opsman::get_director_user() {

    if [[ -z $director_credentials ]]; then
        director_credentials=$(curl -k $OPSMAN_URL/api/v0/deployed/director/credentials/director_credentials \
            -X GET -H "Authorization: Bearer $opsman_token" 2> /dev/null)
    fi
    echo -e "$director_credentials" | $TOOLS_DIR/jq .credential.value.identity | sed 's|"||g'
}

function opsman::get_director_password() {

    if [[ -z $director_credentials ]]; then
        director_credentials=$(curl -k $OPSMAN_URL/api/v0/deployed/director/credentials/director_credentials \
            -X GET -H "Authorization: Bearer $opsman_token" 2> /dev/null)
    fi
    echo -e "$director_credentials" | $TOOLS_DIR/jq .credential.value.password | sed 's|"||g'
}
