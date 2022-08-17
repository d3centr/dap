#!/bin/bash
set -euo pipefail

source ../DaP/load_ENV.sh
: ${DaP_INGRESS:=`env_path $DaP_ENV/cluster/INGRESS`}
env_script=workflow/aws/lib/env.sh
if $DaP_INGRESS; then . $env_script --dns; else . $env_script; fi

ETHEREUM_CLIENT=dap-geth
ETHEREUM_IP=`aws cloudformation list-exports \
    --query "Exports[?Name=='dap-network-eth-ip'].Value" \
    --output text`

subnets=`aws cloudformation list-exports \
    --query "Exports[?starts_with(Name, 'dap-network-subnet-')].[Name, Value]" \
    --output text`
subnet_a=`awk '$1~/a$/{print $2}' <<< "$subnets"`
subnet_b=`awk '$1~/b$/{print $2}' <<< "$subnets"`


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
        - arn:aws:iam::$ACCOUNT:policy/$new-dap-node-$REGION
        `$DaP_INGRESS && echo "- arn:aws:iam::$ACCOUNT:policy/$new-dap-dns-$REGION" || true`
      withAddonPolicies:
        autoScaler: true
"

nodegroups=$({
  read  # first read skips column headers
  while IFS=';' read -r name types volume_size spot desired min max taint; do
  # keep indentation to insert nodegroups into cluster_definition manifest
  echo "
  - name: $name-`$spot && echo spot || echo demand`-a
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
envsubst < workflow/aws/iam/node-policy.json | aws iam create-policy \
    --policy-name $new-dap-node-$REGION --policy-document file:///dev/stdin
if $DaP_INGRESS; then ./workflow/aws/external-dns.sh policy $new $REGION; fi
echo "$cluster_definition" | eksctl create cluster -f /dev/stdin

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
  TEST_BUCKET: $new-dap-$REGION-airflow-$ACCOUNT
  DATA_BUCKET: $new-dap-$REGION-data-$ACCOUNT
  OTHER_DATA_BUCKET: $other-dap-$REGION-data-$ACCOUNT
  DELTA_BUCKET: $new-dap-$REGION-delta-$ACCOUNT
  OTHER_DELTA_BUCKET: $other-dap-$REGION-delta-$ACCOUNT
EOF


echo "DaP ~ tag propagation to autoscaling groups"
# required to scale from 0, could be automatically handled by AWS at some point?
# keep track of feature in parity with unmanaged nodegroups + see comments in ng tags above
# https://eksctl.io/usage/eks-managed-nodes/#feature-parity-with-unmanaged-nodegroups
asg_propagation_keys="
    k8s.io/cluster-autoscaler/node-template/resources/ephemeral-storage
"
./workflow/aws/asg-tag-propagation.sh $new $asg_propagation_keys


## Deploy cluster autoscaler.
echo "DaP ~ autoscaler deployment"
./workflow/aws/autoscaler.sh $new


## Deploy ingress features.
if $DaP_INGRESS; then
    echo "DaP ~ deployment of Load Balancer Controller"
    ./workflow/aws/load-balancer-controller.sh $new
    echo "DaP ~ deployment of external DNS"
    ./workflow/aws/external-dns.sh chart $new
else
    echo "DaP ~ external URL features are disabled in INGRESS configuration: skipping"
fi


## Deploy Argo CD and Workflows.
echo "DaP ~ deployment of Argo CD & Workflows"
./workflow/argo/CD.sh $new
./workflow/argo/workflows.sh $new

