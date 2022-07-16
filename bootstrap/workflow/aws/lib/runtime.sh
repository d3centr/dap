#!/bin/bash

dap_root_path=`git rev-parse --show-toplevel`
dap_shared_flags="--rm -e AWS_PROFILE=$AWS_PROFILE \
    -v $HOME/.aws:/root/.aws -v $HOME/.dap:/root/.dap"

run_workflow () {
    local runtime_name=$1
    local workflow=$2

    # 1. use absolute path to mount local folders
    # 2. leave hardcoded $runtime_name passed from deploy.sh for safety:
    # it ensures that clusters cannot be created concurrently from the same host
    docker run \
        --name $runtime_name \
        $dap_shared_flags \
        -v `pwd`/workflow:/opt/dap \
        -v $dap_root_path/DaP:/opt/DaP \
        -w /opt/dap \
        dap-bootstrap $workflow
}

dap () {
    docker run \
        --name dap-cmd-`date +"%s"` \
        $dap_shared_flags \
        -it \
        -v $HOME/.kube:/root/.kube \
        -v $dap_root_path:$dap_root_path \
        -w `pwd` \
        dap-bootstrap bash -c "`echo \"$@\"`"
}

