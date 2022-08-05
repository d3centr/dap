#!/bin/bash
set -eo pipefail
source workflow/aws/lib/env.sh

help () { echo "
    usage: ./cleanup.sh [<cluster name>] [--policies]
    [...] is optional
    Note: script is usually called from bootstrap/destroy.sh wrapper

    --no-cluster) do not destroy cluster, only IAM policies and load balancer resources:
        useful to clean up account after a failed bootstrap;
        duplicate policy names are not allowed upon creation.
        E.g.: './destroy.sh blue-dap --no-cluster' deletes dangling blue-dap resources.

    -c|--confirm) do not prompt for confirmation
";}

confirm=true
no_cluster=false
while (( $# )); do
    case $1 in
        blue-dap|green-dap) cluster=$1;;
        -c|--confirm) confirm=false;;
        --no-cluster) no_cluster=true;;
        -h|--help) help; exit;;
        -*) echo "unknown $1 option" >&2; help; exit 1;;
    esac
    shift
done
if [ -z $cluster ]; then
    # '|| true' prevents failure when no cluster and bash -e option is set
    cluster=`eksctl get cluster | egrep -o 'blue-dap|green-dap' || true`
    # 'grep -v ^$' removes empty line when no cluster
    if [ `echo "$cluster" | grep -v ^$ | wc -l` -ne 1 ]; then
        echo "Found more or less than a single DaP cluster running: aborting due to ambiguity."
        echo "Pass explicit cluster name to destroy as a single argument and/or --no-cluster flag."
        exit 1
    fi
fi

resources=`$no_cluster && echo 'resources ' || echo ''`
echo "DaP ~ about to destroy $cluster ${resources}in $REGION"
if $confirm; then
    read -p "Press enter to confirm or any character to cancel: "
    if [[ ! $REPLY =~ ^$ ]]; then 
        echo "DaP ~ canceled: $cluster ${resources}will NOT be destroyed"
        exit
    fi
fi
if ! $no_cluster; then
    # AWS_PROFILE sets the cluster region: variable is sourced from runtime.sh in bootstrap/destroy.sh
    eksctl delete cluster --name $cluster
fi


echo "DaP ~ deleting $cluster policies"

default_policies="
    arn:aws:iam::$ACCOUNT:policy/$cluster-node-$REGION
    arn:aws:iam::$ACCOUNT:policy/$cluster-autoscaler-$REGION
"
for policy in $default_policies; do
    echo "DaP ~ deleting $policy"
    aws iam delete-policy --policy-arn $policy || true
done

optional_policies="
    arn:aws:iam::$ACCOUNT:policy/$cluster-dns-$REGION
    arn:aws:iam::$ACCOUNT:policy/$cluster-lbc-$REGION
"
for policy in $optional_policies; do
    echo "DaP ~ deleting $policy"
    aws iam delete-policy --policy-arn $policy || {
        [ $? -eq 254 ] && echo 'DaP ~ expected this error code (254): the policy is optional'
    }
done


echo "DaP ~ deleting $cluster ALB resources (if any)"
./workflow/aws/elb-cleanup.sh $cluster

