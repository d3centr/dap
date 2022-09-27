#!/bin/bash
source init.sh

echo 'DaP ~ running Spark pre-install'

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
kind: ClusterRole
metadata:
  name: spark-submit
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
  - watch
  - list
  - create
  - delete
- apiGroups:
  - ""
  resources:
  - pods/log
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - pods/attach
  verbs:
  - create
- apiGroups:
  - batch
  resources:
  - jobs
  verbs:
  - get
  - create
  - delete
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - create
  - patch
  - delete
- apiGroups:
  - ""
  resources:
  - persistentvolumeclaims
  verbs:
  - list
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - get
  - list
  - create
  - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spark
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: spark-submit
subjects:
- kind: ServiceAccount
  name: spark
  namespace: spark
EOF


# Create global environment variables and main deploy key in spark namespace.
kubectl apply view-last-applied configmap -n default env -o yaml | \
    sed 's/namespace: default/namespace: spark/' | \
    kubectl apply -f -

: ${DaP_SSH_KEY_NAME:=`env_path $DaP_ENV/REPO/SSH_KEY_NAME`}
[ -f /root/.dap/$DaP_SSH_KEY_NAME ] &&
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: dap-deploy-key
  namespace: spark
stringData:
  key: |
`sed 's/^/    /' /root/.dap/$DaP_SSH_KEY_NAME`
EOF


# Create sink + charts buckets and docker registries.

for name in delta charts; do
    bucket=$CLUSTER-$REGION-$name-$ACCOUNT
    aws s3api head-bucket --bucket $bucket || aws s3 mb s3://$bucket
    echo "s3://$bucket"
done

spark_repo=$CLUSTER/spark
for repo in $spark_repo $spark_repo/cache; do
    aws ecr describe-repositories --repository-names $repo ||
        aws ecr create-repository --repository-name $repo
done

cat <<EOF | aws ecr put-lifecycle-policy --repository-name $spark_repo \
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
cat <<EOF | aws ecr put-lifecycle-policy --repository-name $spark_repo/cache \
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


# Provision volume for metastore persistence outside shorter-lived k8s clusters.
source ../bootstrap/workflow/aws/lib/persistent_volume.sh
persistent_volume $PG_VOLUME 8 spark


echo 'DaP ~ stateful Spark resources provisioned'

