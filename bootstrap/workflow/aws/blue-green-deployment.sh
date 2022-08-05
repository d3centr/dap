#!/bin/bash
set -euo pipefail

source aws/lib/env.sh
source ../DaP/load_ENV.sh

ETHEREUM_CLIENT=dap-geth

ETHEREUM_IP=`aws cloudformation list-exports \
    --query "Exports[?Name=='dap-network-eth-ip'].Value" \
    --output text`

subnets=`aws cloudformation list-exports \
    --query "Exports[?starts_with(Name, 'dap-network-subnet-')].[Name,Value]" \
    --output text`
subnet_a=`echo "$subnets" | awk '$1~/subnet-a$/{print $2}'`
subnet_b=`echo "$subnets" | awk '$1~/subnet-b$/{print $2}'`


## Determine new cluster color according to blue-green deployment workflow.
clusters=`eksctl get cluster`

if echo $clusters | egrep -q 'No clusters? found'; then

    echo "DaP ~ no cluster found"
    old=none
    export new=blue
    other=green

elif [ `echo "$clusters" | egrep 'blue-dap|green-dap' | wc -l` -gt 1 ]; then

    echo 'DaP ~ Skipping cluster creation: found more than a running colored cluster in region.'
    exit 1

elif echo $clusters | grep -q blue-dap; then

    echo "DaP ~ blue cluster found"
    old=blue
    export new=green
    other=$old

elif echo $clusters | grep -q green-dap; then

    echo "DaP ~ green cluster found"
    old=green
    export new=blue
    other=$old

elif [ -z $new ]; then

    echo "DaP ~ Issue encountered determining new cluster color: debug if statements in $0."
    exit 1

fi


## Create Kubernetes cluster.
echo "DaP ~ creating $new cluster"

policies="
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
        - arn:aws:iam::$ACCOUNT:policy/$new-dap-node
      withAddonPolicies:
        autoScaler: true
"

nodegroups=$({
  read  # first read skips column headers
  while IFS=';' read -r name types volume_size spot desired min max taint; do
  # keep indentation to insert nodegroups into cluster_definition manifest
  echo "
  - name: $name-`[ $spot = true ] && echo spot || echo demand`-a
    subnets: [$subnet_a]
    instanceTypes: [$types]
    # keep volumeSize > 8 to avoid NodeHasDiskPressure
    volumeSize: $volume_size
    spot: $spot
    desiredCapacity: $desired
    minSize: $min
    maxSize: $max
    # labels and taints must also be tagged to scale from 0
    taints: `[ -z $taint ] && echo '[]' || echo \"
      - key: $taint
        value: exec
        effect: NoSchedule
    \"`
    tags:
      # trigger autoscaling from 0 with ephemeral storage request
      # https://github.com/weaveworks/eksctl/issues/1571#issuecomment-785789833
      # manual propagation to ASG still required: see after cluster creation
      # confused follow up in https://github.com/weaveworks/eksctl/issues/5420
      k8s.io/cluster-autoscaler/node-template/resources/ephemeral-storage: ${volume_size}Gi
      `[ -z $taint ] || echo \"k8s.io/cluster-autoscaler/node-template/taint/$taint: 'exec:NoSchedule'\"`
    iam: $policies
  "
done } < `env_file $DaP_ENV/cluster/nodegroups`)

cluster_definition="
  apiVersion: eksctl.io/v1alpha5
  kind: ClusterConfig  
  metadata:
    name: $new-dap
    region: $REGION
  iam:
    withOIDC: true
  vpc:
    subnets:
      public:
        subnet-a:
          id: $subnet_a
        subnet-b:
          id: $subnet_b
  managedNodeGroups: $nodegroups
"
echo "$cluster_definition" | eksctl create cluster -f /dev/stdin --dry-run

# Variables interpolated by envsubst in json policy must be exported beforehand, e.g. export new=color. 
envsubst < aws/iam/node-policy.json | 
    aws iam create-policy --policy-name $new-dap-node --policy-document file:///dev/stdin

echo "$cluster_definition" | eksctl create cluster -f /dev/stdin

echo "DaP ~ tag propagation to autoscaling groups"
# required to scale from 0, could be automatically handled by AWS at some point
# keep track of feature in parity with unmanaged nodegroups
# https://eksctl.io/usage/eks-managed-nodes/#feature-parity-with-unmanaged-nodegroups

asg_propagation_tags="
    k8s.io/cluster-autoscaler/node-template/resources/ephemeral-storage
"
nodegroups=`aws eks list-nodegroups --cluster-name $new-dap --no-paginate \
    --query nodegroups --output text`

for ng in $nodegroups; do

    asg=`aws eks describe-nodegroup --cluster-name $new-dap --nodegroup-name $ng \
        --query nodegroup.resources.autoScalingGroups --output text`

    ng_tags=`aws eks describe-nodegroup --cluster-name $new-dap --nodegroup-name $ng \
        --query nodegroup.tags --output table | tr -d ' '`

    for tag in $asg_propagation_tags; do
        value=`echo "$ng_tags" | awk -F'|' '$2=="'$tag'"{print $3}'`
        aws autoscaling create-or-update-tags --tags \
            ResourceId=$asg,ResourceType=auto-scaling-group,Key=$tag,Value=$value,PropagateAtLaunch=true
    done

done

# Create global variables.
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: env
  namespace: default
data:
  ETHEREUM_CLIENT: $ETHEREUM_CLIENT
  ETHEREUM_IP: $ETHEREUM_IP
  SUBNET_A: $subnet_a
  REGISTRY: $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/$new-dap
  KUBECTL_VERSION: $KUBECTL_VERSION
  LOG_BUCKET: $new-dap-$REGION-log-$ACCOUNT
  DATA_BUCKET: $new-dap-$REGION-data-$ACCOUNT
  OTHER_DATA_BUCKET: $other-dap-$REGION-data-$ACCOUNT
  DELTA_BUCKET: $new-dap-$REGION-delta-$ACCOUNT
  OTHER_DELTA_BUCKET: $other-dap-$REGION-delta-$ACCOUNT
EOF


## Deploy cluster autoscaler.
echo "DaP ~ autoscaler deployment"

aws iam create-policy \
    --policy-name $new-dap-cluster-autoscaler \
    --policy-document file://aws/iam/cluster-autoscaler-policy.json

eksctl create iamserviceaccount \
    --cluster=$new-dap \
    --namespace=kube-system \
    --name=cluster-autoscaler \
    --attach-policy-arn=arn:aws:iam::$ACCOUNT:policy/$new-dap-cluster-autoscaler \
    --override-existing-serviceaccounts \
    --approve

cluster_version=`kubectl version --short=true | grep -oP '(?<=Server Version: v)[0-9]+\.[0-9]+'`
autoscaler_version=`curl -s https://api.github.com/repos/kubernetes/autoscaler/tags?per_page=100 |
    grep -oP "(?<=\"name\": \"cluster-autoscaler-)$cluster_version\.[0-9]+" |
    head -1`

# Do not add in application layer, e.g. Argo CD.
# Autoscaler should be part of infrastructure layer for app dependencies on compute capacity.
helm install \
    --namespace kube-system \
    --set clusterName=$new-dap,imageVersion=$autoscaler_version \
    cluster-autoscaler ./aws/helm/cluster-autoscaler


## Deploy metrics server
echo "DaP ~ metrics server deployment"

ms_releases=https://github.com/kubernetes-sigs/metrics-server/releases
: ${DaP_METRICS_SERVER:=`env_path $DaP_ENV/version/METRICS_SERVER`}
kubectl apply -f $ms_releases/download/v$DaP_METRICS_SERVER/components.yaml


## Deploy Argo CD and Workflows.
echo "DaP ~ deployment of Argo CD & Workflows"
./argo/CD.sh $new
./argo/workflows.sh

