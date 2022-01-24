#!/bin/bash
set -euo pipefail

REPO=https://github.com/d3centr/blake.git
BRANCH=`git symbolic-ref HEAD --short`

authenticate_with_last_cluster_created () {
    local clusters=`aws eks list-clusters --query clusters --output text --no-paginate | \
        egrep -o '(blue|green)-blake'`

    local creation_times=`for cluster in $clusters; do
        aws eks describe-cluster --name $cluster --query cluster.[name,createdAt] --output text; done`

    local last_cluster_created=`echo "$creation_times" | sort -V | tail -1 | cut -f1`

    aws eks update-kubeconfig --name $last_cluster_created
}

# When both blue and green-blake run, the first cluster created is immutable. No reason to touch it.
authenticate_with_last_cluster_created
read REGION ACCOUNT CLUSTER <<< `kubectl config current-context | awk -F'[:/]' '{print $4,$5,$NF}'`
REGISTRY=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$CLUSTER

export ARGOCD_OPTS='--port-forward-namespace argocd'
# prevent pre-install scripts from getting stuck on pagination in small terminal windows
export AWS_PAGER=

