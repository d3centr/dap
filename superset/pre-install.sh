#!/bin/bash
source init.sh

echo 'DaP ~ running Superset pre-install'

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: superset
EOF


# Create global environment variables in superset namespace.
kubectl apply view-last-applied configmap -n default env -o yaml | \
    sed 's/namespace: default/namespace: superset/' | \
    kubectl apply -f -


# Provision volume for Superset persistence outside shorter-lived k8s clusters.
source ../bootstrap/workflow/aws/lib/persistent_volume.sh
persistent_volume $PG_VOLUME 8 superset


# Create docker registries.
superset_repo=$CLUSTER/superset
aws ecr describe-repositories --repository-names $superset_repo ||
    aws ecr create-repository --repository-name $superset_repo
aws ecr describe-repositories --repository-names $superset_repo/cache ||
    aws ecr create-repository --repository-name $superset_repo/cache

cat <<EOF | aws ecr put-lifecycle-policy --repository-name $superset_repo \
    --lifecycle-policy-text file:///dev/stdin
{
   "rules": [
       {
           "rulePriority": 1,
           "selection": {
               "tagStatus": "untagged",
               "countType": "sinceImagePushed",
               "countUnit": "days",
               "countNumber": 15
           },
           "action": {
               "type": "expire"
           }
       }
   ]
}
EOF
cat <<EOF | aws ecr put-lifecycle-policy --repository-name $superset_repo/cache \
    --lifecycle-policy-text file:///dev/stdin
{
   "rules": [
       {
           "rulePriority": 1,
           "selection": {
               "tagStatus": "any",
               "countType": "sinceImagePushed",
               "countUnit": "days",
               "countNumber": 30
           },
           "action": {
               "type": "expire"
           }
       }
   ]
}
EOF


echo 'DaP ~ stateful Superset resources provisioned'

