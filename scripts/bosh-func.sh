#!/bin/bash

if [[ -z $TOOLS_DIR ]]; then
    source $(dirname $0)/common.sh
fi

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

function bosh::login() {

    local director_ip=$1
    local user=$2
    local password=$3

    logged_in_user=$(echo -e "$bosh_status" | awk '/User/{ print $ 2}')
    if [[ "$user" != "$logged_in_user" ]]; then
        $bosh logout
        echo -e "Targetting director."
        echo -e "$user\n$password" | $bosh --ca-cert //var/tempest/workspaces/default/root_ca_certificate target $director_ip
    fi
}

function bosh::status() {
    bosh_status=$($bosh status)
    echo -e "Status of currently targeted Bosh director..."
    echo -e "$bosh_status"
}

function bosh::vms() {

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

    local dep_prefix=$1

    bosh_deployment=$($bosh deployments | awk -v d="$dep_prefix-" '$2~d { print $2 }')
    if [[ -z $bosh_deployment ]]; then
        echo "Unable to determine name for deployment prefix '$dep_prefix'."
        exit 1
    fi

    rm -f $dep_prefix.yml
    $bosh download manifest $bosh_deployment $dep_prefix.yml
    $bosh deployment $dep_prefix.yml
}

function bosh::job() {
    job_name=${1%%/*}
    job_index=${1##*/}
    echo "Stopping job '$job_name' index '$job_index'..."
    echo "yes" | $bosh stop $job_name $job_index
}

function bosh::job() {
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
