#!/bin/bash
set -euo pipefail
#
# Manual run from bootstrap folder:
# . runtime.sh
# run_workflow . workflow/aws/lib/env.sh\; workflow/aws/autoscaler.sh blue
source ../DaP/load_ENV.sh

color=$1
aws eks update-kubeconfig --name $color-dap

policy_name=$color-dap-autoscaler-$REGION
aws iam create-policy --policy-name $policy_name \
    --policy-document file://workflow/aws/iam/cluster-autoscaler-policy.json

eksctl create iamserviceaccount \
    --cluster=$color-dap \
    --namespace=kube-system \
    --name=cluster-autoscaler \
    --attach-policy-arn=arn:aws:iam::$ACCOUNT:policy/$policy_name \
    --override-existing-serviceaccounts \
    --approve

cluster_version=`kubectl version --short=true | grep -oP '(?<=Server Version: v)[0-9]+\.[0-9]+'`
autoscaler_version=`curl -s https://api.github.com/repos/kubernetes/autoscaler/tags?per_page=100 |
    grep -oP "(?<=\"name\": \"cluster-autoscaler-)$cluster_version\.[0-9]+" |
    head -1`

# Do not add in application layer, e.g. Argo CD.
# Autoscaler should be part of infrastructure layer for app dependencies on compute capacity.
helm upgrade -i --namespace kube-system \
    --set clusterName=$color-dap,imageVersion=$autoscaler_version \
    cluster-autoscaler ./workflow/aws/helm/cluster-autoscaler


## Deploy metrics server
echo "DaP ~ metrics server deployment"

ms_releases=https://github.com/kubernetes-sigs/metrics-server/releases
: ${DaP_METRICS_SERVER:=`env_path $DaP_ENV/version/METRICS_SERVER`}
kubectl apply -f $ms_releases/download/v$DaP_METRICS_SERVER/components.yaml

