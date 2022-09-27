#!/bin/bash
# CAUTION: for deterministic results, better not to edit files while a runtime is running.
# Local DaP repository is the source of truth.

dap_root_path=`git rev-parse --show-toplevel`
# - use absolute path to mount local folders
# - AWS_PROFILE and DaP variables are not included for dynamic loading
dap_shared_flags="--rm -it
    -v $HOME/.aws:/root/.aws
    -v $HOME/.dap:/root/.dap
    -v $dap_root_path:$dap_root_path
"

DaP_variables () {
    # when no DaP variable is defined, `declare` processes all others without this check
    [ `wc -w <<< ${!DaP_@}` -gt 0 ] &&
        declare -p ${!DaP_@} | tr -d '"' | awk '{print "-e "$NF}'
}

run_workflow () {
    local RUNTIME_NAME=dap-workflow

    # - Leave hardcoded RUNTIME_NAME for safety:
    # it ensures that commands dependent on the local file system cannot run concurrently.
    docker run \
        --name $RUNTIME_NAME \
        $dap_shared_flags \
        `DaP_variables` \
        -e AWS_PROFILE=$AWS_PROFILE \
        -w $dap_root_path/bootstrap \
        dap-bootstrap bash -c "`echo $@`"
}

# unsafe but more versatile version of run_workflow for any admin task
# avoid parallel calls unless you know what you are doing, for expected behavior:
# at least kubeconfig and AWS profile should remain the same across concurrent runs
dap () {
    docker run \
        --name dap-cmd-`date +"%s"` \
        $dap_shared_flags \
        `DaP_variables` \
        -e AWS_PROFILE=$AWS_PROFILE \
        -v $HOME/.kube:/root/.kube \
        -w `pwd` \
        dap-bootstrap bash -c "`echo $@`"
}

