#!/bin/bash
source init.sh

## Create stateful Airflow resources when not available.

# Idempotent Airflow components are synchronized by Argo CD.
# Resources below have their own lifecycle due to external parameters or historical data.
# See airflow/cleanup.sh to delete aws resources AND data (at your discretion).

echo 'DaP ~ running Airflow pre-install'

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: airflow
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spark-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: spark-submit
subjects:
- kind: ServiceAccount
  name: airflow-worker
  namespace: airflow
EOF


# Create global environment variables in airflow namespace.
kubectl apply view-last-applied configmap -n default env -o yaml | \
    sed 's/namespace: default/namespace: airflow/' | \
    kubectl apply -f -


# Provision volume for Airflow records outside shorter-lived k8s clusters.
source ../bootstrap/workflow/aws/lib/persistent_volume.sh
persistent_volume $PG_VOLUME 8 airflow


# Create docker registry and buckets.
airflow_repo=$CLUSTER/airflow
aws ecr describe-repositories --repository-names $airflow_repo ||
    aws ecr create-repository --repository-name $airflow_repo
aws ecr describe-repositories --repository-names $airflow_repo/cache ||
    aws ecr create-repository --repository-name $airflow_repo/cache

cat <<EOF | aws ecr put-lifecycle-policy --repository-name $airflow_repo \
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
cat <<EOF | aws ecr put-lifecycle-policy --repository-name $airflow_repo/cache \
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

airflow_bucket=$CLUSTER-$REGION-airflow-$ACCOUNT
aws s3api head-bucket --bucket $airflow_bucket || aws s3 mb s3://$airflow_bucket
echo "s3://$airflow_bucket"
# API is expecting a prefix: set empty
cat <<EOF | aws s3api put-bucket-lifecycle-configuration \
    --bucket $airflow_bucket \
    --lifecycle-configuration file:///dev/stdin
{
    "Rules": [
        {
            "Status": "Enabled",
            "Expiration": {
                "Days": 30
            },
            "Prefix": ""
        }
    ]
}
EOF

data_bucket=$CLUSTER-$REGION-data-$ACCOUNT
aws s3api head-bucket --bucket $data_bucket || aws s3 mb s3://$data_bucket
echo "s3://$data_bucket"


echo 'DaP ~ stateful Airflow resources provisioned'

