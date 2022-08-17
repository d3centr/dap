#!/bin/bash
set -euo pipefail
source ../DaP/load_ENV.sh

env_branch () { 
    local branch=`env_path $DaP_ENV/BRANCH`
    [ $branch = _local ] && git symbolic-ref HEAD --short || echo $branch
}
: ${DaP_REPO:=`env_path $DaP_ENV/REPO`}
: ${DaP_SYNC:=`env_path $DaP_ENV/SYNC`}
: ${DaP_BRANCH:=`env_branch`}

# When both blue and green-dap run, the first cluster created is immutable. No reason to touch it.
root=`git rev-parse --show-toplevel`
$root/bootstrap/workflow/aws/lib/authenticate_with_last_cluster_created.sh
read REGION ACCOUNT CLUSTER <<< `kubectl config current-context | awk -F'[:/]' '{print $4,$5,$NF}'`
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$CLUSTER
# default for local spark submit override of sink bucket
DELTA_BUCKET=$CLUSTER-$REGION-delta-$ACCOUNT

# --plaintext disables TLS on client because it is disabled on server (configured on LB)
# + kubectl port-forward goes through an encrypted TLS tunnel
export ARGOCD_OPTS='--port-forward-namespace argocd --plaintext'
# export variable referenced in envsubst pipes
export REGION
# prevent pre-install scripts from getting stuck on pagination in small terminal windows
export AWS_PAGER=

printf "\n        - Defined -\n"
echo "DaP_ENV    = $DaP_ENV"
echo "DaP_REPO   = $DaP_REPO"
echo "DaP_SYNC   = $DaP_SYNC"
echo "DaP_BRANCH = $DaP_BRANCH"
echo "CLUSTER    = $CLUSTER"
printf "\n        - Exported -\n"
echo "REGION     = $REGION"
echo ""

