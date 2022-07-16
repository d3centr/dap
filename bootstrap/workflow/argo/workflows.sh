#!/bin/bash
source ../DaP/load_ENV.sh
: ${DaP_ARGO_WF_CHART:=`env_path $DaP_ENV/version/ARGO_WF_CHART`}

helm repo add argo https://argoproj.github.io/argo-helm
helm install --namespace argo --create-namespace \
    --version $DaP_ARGO_WF_CHART \
    --set server.extraArgs={--auth-mode=server} \
    --set workflow.serviceAccount.create=true wf argo/argo-workflows

