#!/bin/bash

export ROOT_DIR=$(cd $(dirname $0)/.. && pwd)
export CURR_DIR=$(pwd)

case $(uname) in
    Linux)
        TOOLS_DIR=$ROOT_DIR/tools/linux
        ;;
    Darwin)
        TOOLS_DIR=$ROOT_DIR/tools/darwin
        ;;
    *)
        echo "ERROR: Unable to identify OS type."
        exit 1
esac
