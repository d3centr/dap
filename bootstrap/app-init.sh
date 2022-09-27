#!/bin/bash
set -euo pipefail
source ../DaP/load_ENV.sh

: ${DaP_REPO:=`env_path $DaP_ENV/REPO`}
: ${DaP_SYNC:=`env_path $DaP_ENV/SYNC`}
: ${DaP_BRANCH:=`env_branch`}
: ${DaP_KANIKO:=`env_path $DaP_ENV/tag/KANIKO`}

# When both blue and green-dap run, the first cluster created is immutable. No reason to touch it.
root=`git rev-parse --show-toplevel`
$root/bootstrap/workflow/aws/lib/authenticate_with_last_cluster_created.sh
read REGION ACCOUNT CLUSTER <<< `kubectl config current-context | awk -F'[:/]' '{print $4,$5,$NF}'`
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$CLUSTER

# --plaintext disables TLS on client because it is disabled on server (configured on LB)
# port-forward goes through an encrypted TLS tunnel when argo isn't called inside cluster (wf)
set +u  # allowing unset ARGO_NODE_ID on local file system
if [[ $ARGO_NODE_ID =~ ^install- ]]; then
    export ARGOCD_OPTS='--server argocd-server.argocd.svc.cluster.local:80 --plaintext'
else
    export ARGOCD_OPTS='--port-forward-namespace argocd --plaintext'
fi
set -u
# prevent pre-install scripts from getting stuck on pagination in small terminal windows
export AWS_PAGER=

echo
echo "DaP_ENV    = $DaP_ENV"
echo "DaP_REPO   = $DaP_REPO"
echo "DaP_SYNC   = $DaP_SYNC"
echo "DaP_BRANCH = $DaP_BRANCH"
echo "CLUSTER    = $CLUSTER"
echo

