#!/bin/bash
set -euo pipefail
#
# Manual run from bootstrap folder:
# . runtime.sh
# run_workflow . workflow/aws/lib/env.sh --dns\; workflow/argo/workflows.sh blue
source ../DaP/load_ENV.sh
: ${DaP_ARGO_WF_CHART:=`env_path $DaP_ENV/version/ARGO_WF_CHART`}
: ${DaP_INGRESS:=`env_path $DaP_ENV/cluster/INGRESS`}

color=$1
aws eks update-kubeconfig --name $color-dap

helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade -i --namespace argo --create-namespace \
    --version $DaP_ARGO_WF_CHART \
    --set server.extraArgs={--auth-mode=server} \
    --set workflow.serviceAccount.create=true \
    wf argo/argo-workflows

if $DaP_INGRESS; then 
    DaP_ingress $color/argo/wf-argo-workflows-server/2746 argo; fi

