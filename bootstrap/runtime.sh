#!/bin/bash

# otherwise, pass first argument through when runtime.sh is sourced
if [[ $# -gt 0 && $1 = build ]]; then
    cmd=build
else
    cmd=load
fi
case $cmd in

    build)

        source ../DaP/load_ENV.sh
        : ${DaP_DEBIAN:=`env_path $DaP_ENV/tag/DEBIAN`}
        : ${DaP_AWSCLI:=`env_path $DaP_ENV/version/AWSCLI`}
        : ${DaP_EKSCTL:=`env_path $DaP_ENV/version/EKSCTL`}
        : ${DaP_KUBECTL:=`env_path $DaP_ENV/version/KUBECTL`}
        : ${DaP_HELM:=`env_path $DaP_ENV/version/HELM`}
        : ${DaP_ARGO_CD:=`env_path $DaP_ENV/version/ARGO_CD`}
        : ${DaP_ARGO_WF_CHART:=`env_path $DaP_ENV/version/ARGO_WF_CHART`}

        echo "DaP ~ building bootstrap environment"
        docker build \
            --build-arg DEBIAN_TAG=$DaP_DEBIAN \
            --build-arg AWSCLI_VERSION=$DaP_AWSCLI \
            --build-arg EKSCTL_VERSION=$DaP_EKSCTL \
            --build-arg KUBECTL_VERSION=$DaP_KUBECTL \
            --build-arg HELM_VERSION=$DaP_HELM \
            --build-arg ARGO_CD_VERSION=$DaP_ARGO_CD \
            --build-arg ARGO_WF_CHART_VERSION=$DaP_ARGO_WF_CHART \
            -t dap-bootstrap .

    ;;

    load)

        lib_path=`git rev-parse --show-toplevel`/bootstrap/workflow/aws/lib
        source $lib_path/profile-configuration.sh
        source $lib_path/runtime.sh

    ;;

esac

