#!/bin/bash

if [[ -z $ROOT_DIR ]]; then
    ROOT_DIR=$(cd $(dirname $0)/.. && pwd)
fi
if [[ -z $TOOLS_DIR ]]; then
    source $ROOT_DIR/scripts/common.sh
fi

function bosh::set_bosh_cli() {
    which bosh 2>&1 > /dev/null
    if [ $? -ne 0 ]; then
        which bundle 2>&1 > /dev/null
        if [ $? -ne 0 ]; then
            echo "ERROR! Unable to find bosh cli."
            exit 1
        fi
        export BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile 
        bosh="bundle exec bosh"
    else
        bosh="bosh"
    fi
}

function bosh::status() {
    bosh::set_bosh_cli

    if [[ -z $bosh_status ]]; then
        bosh_status=$($bosh status)
    fi
    echo -e "Status of currently targeted Bosh director..."
    echo -e "$bosh_status"
}

function bosh::login() {
    bosh::set_bosh_cli

    local director_ip=$1
    local user=$2
    local password=$3

    logged_in_user=$(bosh::status | awk '/User/{ print $ 2}')
    if [[ "$user" != "$logged_in_user" ]]; then
        $bosh logout
        echo -e "Targetting director."
        echo -e "$user\n$password" | $bosh --ca-cert //var/tempest/workspaces/default/root_ca_certificate target $director_ip
    fi
}

function bosh::vms() {
    bosh::set_bosh_cli

    local deployment=$1

    bosh_vms=$($bosh vms $deployment --vitals)
    if [[ -n $deployment ]]; then
        echo -e "Status of all VMs in deployment '$deployment'..."
    else
        echo -e "Status of all VMs..."
    fi
    echo -e "$bosh_vms"
}

function bosh::set_deployment() {
    bosh::set_bosh_cli

    local dep_prefix=$1
    local manifest_file=$(bosh::status | awk '/Manifest/{ print $ 2}')

    if [[ "$manifest_file"!="/tmp/$dep_prefix.yml" ]]
        bosh_deployment=$($bosh deployments 2>/dev/null | awk -v d="$dep_prefix-" '$2~d { print $2 }')
        if [[ -z $bosh_deployment ]]; then
            echo "Unable to determine name for deployment prefix '$dep_prefix'."
            exit 1
        fi
        $bosh download manifest $bosh_deployment /tmp/$dep_prefix.yml 2>&1 > /dev/null
        $bosh deployment /tmp/$dep_prefix.yml 2>&1 > /dev/null
    fi
}

function bosh::stop_job() {
    bosh::set_bosh_cli

    job_name=${1%%/*}
    job_index=${1##*/}
    echo "Stopping job '$job_name' index '$job_index'..."
    echo "yes" | $bosh stop $job_name $job_index
}

function bosh::start_job() {
    bosh::set_bosh_cli

    job_name=${1%%/*}
    job_index=${1##*/}
    echo "Starting job '$job_name' index '$job_index'..."
    echo "yes" | $bosh start $job_name $job_index
}

function bosh::restart_job() {

    local job_prefix=$1

    if [[ -n $job_prefix ]]; then
        for j in $(echo -e "$bosh_vms" | awk -v j="$job_prefix-" '$2~j { print $2 }'); do
            bosh::stop_job $j
        done
        for j in $(echo -e "$bosh_vms" | awk -v j="$job_prefix-" '$2~j { print $2 }'); do
            bosh::start_job $j
        done
    fi
}
