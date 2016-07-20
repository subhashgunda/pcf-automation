#!/bin/bash

set -x
set -e

if [[ "@option.clean@" == "1" ]]; then
	rm -fr /tmp/pcf-config
fi

mkdir -p /tmp/pcf-config
cd /tmp/pcf-config

export PATH=/tmp/pcf-config/pcf-automation:$PATH

if [[ ! -e pcf-automation ]]; then
	curl -v -s -k -L https://@node.bitbucket@/plugins/servlet/archive/projects/CLOUDF/repos/pcf-automation -o pcf-automation.zip
	unzip  -o pcf-automation.zip -d pcf-automation
fi

curl -v -s -k -L https://@node.bitbucket@/plugins/servlet/archive/projects/CLOUDF/repos/pcf-config-ch-dev -o pcf-config-ch-dev.zip

run_job=1
if [[ -e pcf-config-ch-dev.zip.last ]]; then
	set +e
    diff pcf-config-ch-dev.zip pcf-config-ch-dev.zip.last
    if [[ $? -ne 2 ]]; then
        run_job=0
    fi
    set -e
fi

if [[ $run_job -eq 1 ]]; then

    echo "Running Configuration!"

	rm -fr pcf-config-ch-dev
	unzip  -o pcf-config-ch-dev.zip -d pcf-config-ch-dev

	cd pcf-config-ch-dev
	if [ "@option.opsman-key@" = "" ]; then
		configure-ert -o @option.opsman-host@ -u @option.opsman-user@ -p @option.opsman-password@
	else
		configure-ert -o @option.opsman-host@ -u @option.opsman-user@ -p @option.opsman-password@ -k @option.opsman-key@
	fi
	cd ..

    mv pcf-config-ch-dev.zip pcf-config-ch-dev.zip.last
else
    rm pcf-config-ch-dev.zip
fi

set +e
set +x
