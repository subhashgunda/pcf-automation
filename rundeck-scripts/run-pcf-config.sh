#!/bin/bash

set -x
set -e

mkdir -p /tmp/pcf-config
cd /tmp/pcf-config

curl -v -s -L https:/@node.bitbucket@/plugins/servlet/archive/projects/CLOUDF/repos/pcf-automation -o pcf-automation.zip
unzip pcf-automation.zip -o -d pcf-automation

curl -v -s -L https://@node.bitbucket@/plugins/servlet/archive/projects/CLOUDF/repos/pcf-config-ch-dev -o pcf-config-ch-dev.zip

run_job=1
if [[ -e pcf-config-ch-dev.zip.last ]]; then
    diff pcf-config-ch-dev.zip pcf-config-ch-dev.zip.last
    if [[ $? -ne 2 ]]; then
        run_job=0
    fi
fi

if [[ $run_job -eq 1 ]]; then
    echo "Running Configuration!"
    mv pcf-config-ch-dev.zip pcf-config-ch-dev.zip.last
else
    rm pcf-config-ch-dev.zip
fi

set +e
set +x
