#!/bin/bash
set -euo pipefail
#
# Manual run from bootstrap folder:
# . runtime.sh
# keys="
#     k8s.io/cluster-autoscaler/node-template/resources/ephemeral-storage
# "
# run_workflow workflow/aws/asg-tag-propagation.sh blue $keys

color=$1
aws eks update-kubeconfig --name $color-dap
asg_propagation_keys=${@:2}

nodegroups=`aws eks list-nodegroups --cluster-name $color-dap --no-paginate \
    --query nodegroups --output text`
for ng in $nodegroups; do

    asg=`aws eks describe-nodegroup --cluster-name $color-dap --nodegroup-name $ng \
        --query nodegroup.resources.autoScalingGroups --output text`

    ng_tags=`aws eks describe-nodegroup --cluster-name $color-dap --nodegroup-name $ng \
        --query nodegroup.tags --output table | tr -d ' '`

    for key in $asg_propagation_keys; do
        value=`echo "$ng_tags" | awk -F'|' '$2=="'$key'"{print $3}'`
        aws autoscaling create-or-update-tags --tags \
            ResourceId=$asg,ResourceType=auto-scaling-group,Key=$key,Value=$value,PropagateAtLaunch=true
    done

done

