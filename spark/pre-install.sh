#!/bin/bash
source init.sh

echo 'BLAKE ~ running Spark pre-install'

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: spark
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark
  namespace: spark
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spark
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
- kind: ServiceAccount
  name: spark
  namespace: spark
EOF


# Create global environment variables in spark namespace.
kubectl apply view-last-applied configmap -n default env -o yaml | \
    sed 's/namespace: default/namespace: spark/' | \
    kubectl apply -f -


# Create docker registry and sink bucket.
spark_repo=$CLUSTER/spark
aws ecr describe-repositories --repository-names $spark_repo ||
    aws ecr create-repository --repository-name $spark_repo

delta_bucket=$CLUSTER-$REGION-delta-$ACCOUNT
aws s3api head-bucket --bucket $delta_bucket || aws s3 mb s3://$delta_bucket
echo "s3://$delta_bucket"


# Provision volume for metastore persistence outside shorter-lived k8s clusters.
source ../bootstrap/workflow/aws/lib/persistent_volume.sh
persistent_volume $PG_VOLUME 8 spark


echo 'BLAKE ~ stateful Spark resources provisioned'

