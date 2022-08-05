#!/bin/bash
cluster=$1
KEY=elbv2.k8s.aws/cluster
TAG='`{"Key": "'$KEY'", "Value": "'$cluster'"}`'

# Load Balancers
echo "DaP ~ scanning $cluster Load Balancers"
lbs=`aws elbv2 describe-load-balancers --no-paginate --output text \
    --query LoadBalancers[].LoadBalancerArn`
if [ -n "$lbs" ]; then
    tagged_lbs=`aws elbv2 describe-tags --resource-arns $lbs --output text \
        --query "TagDescriptions[?contains(Tags, $TAG)].ResourceArn"`
    for lb in $tagged_lbs; do
        echo "DaP ~ deleting $lb"
        aws elbv2 delete-load-balancer --load-balancer-arn $lb
    done
fi

# Target Groups
echo "DaP ~ scanning $cluster Target Groups"
tgs=`aws elbv2 describe-target-groups --no-paginate --output text \
    --query TargetGroups[].TargetGroupArn`
if [ -n "$tgs" ]; then
    tagged_tgs=`aws elbv2 describe-tags --resource-arns $tgs --output text \
        --query "TagDescriptions[?contains(Tags, $TAG)].ResourceArn"`
    for tg in $tagged_tgs; do
        echo "DaP ~ deleting $tg"
        aws elbv2 delete-target-group --target-group-arn $tg
    done
    sleep 3  # buffer to prevent DependencyViolation error when deleting SGs
fi

# Security Groups
echo "DaP ~ scanning load balancer Security Groups"
sgs=`aws ec2 describe-security-groups --no-paginate --output text \
    --filters Name=tag:$KEY,Values=$cluster --query SecurityGroups[].GroupId`
for sg in $sgs; do
    echo "DaP ~ deleting $sg"
    aws ec2 delete-security-group --group-id $sg
done

