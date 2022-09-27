#!/bin/bash
source init.sh

# $TAG is reserved in Fluent Bit s3_key_format (prepend IMAGE_)
IFS=: read IMAGE IMAGE_TAG <<< "`aws ssm get-parameters-by-path \
    --path /aws/service/aws-for-fluent-bit \
    --query "Parameters[?Name=='/aws/service/aws-for-fluent-bit/stable'].Value" \
    --output text`"

export REGION IMAGE IMAGE_TAG
envsubst '$LOG_BUCKET $REGION $IMAGE $IMAGE_TAG' < values.yaml.tpl | 
    argocd app create log --values-literal-file /dev/stdin \
        --upsert \
        --repo $DaP_REPO \
        --revision $DaP_BRANCH \
        --path log \
        --dest-namespace logging \
        --dest-server https://kubernetes.default.svc \
        --sync-policy $DaP_SYNC \
        `[ $DaP_SYNC != none ] && echo --auto-prune --self-heal`

