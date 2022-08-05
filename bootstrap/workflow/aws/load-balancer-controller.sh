#!/bin/bash
set -euo pipefail
#
# Manual run from bootstrap folder:
# . runtime.sh
# run_workflow . workflow/aws/lib/env.sh\; workflow/aws/load-balancer-controller.sh blue
source ../DaP/load_ENV.sh
: ${DaP_AWSLBC:=`env_path $DaP_ENV/version/AWSLBC`}

color=$1
aws eks update-kubeconfig --name $color-dap

lbc_source=https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller
policy_name=$color-dap-lbc-$REGION
curl $lbc_source/v$DaP_AWSLBC/docs/install/iam_policy.json |
    aws iam create-policy --policy-name $policy_name --policy-document file:///dev/stdin

eksctl create iamserviceaccount \
  --cluster $color-dap \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::$ACCOUNT:policy/$policy_name \
  --override-existing-serviceaccounts \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update
lbc_chart_version=`helm search repo eks/aws-load-balancer-controller --versions |
    awk '$3=="v'$DaP_AWSLBC'"{print $2}' | head -1`

grep -q $REGION workflow/aws/lib/regional-ecr.tsv || { 
    echo "DaP ~ installation of AWS Load Balancer Controller failed:"
    echo "DaP ~ private $REGION ECR is missing from bootstrap/workflow/aws/lib/regional-ecr.tsv"
    echo "DaP ~ either review regional-ecr.tsv or deploy DaP in another region for DNS features"
    exit 1
}
lbc_registry=`cat workflow/aws/lib/regional-ecr.tsv | awk '$1=="'$REGION'"{print $2}'`

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version $lbc_chart_version \
  -n kube-system \
  --set clusterName=$color-dap \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set image.repository=$lbc_registry/amazon/aws-load-balancer-controller

