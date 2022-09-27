#!/bin/bash

cluster=$1
if [ -z $cluster ]; then
    echo 'Cluster name argument is missing, e.g. run `./cleanup.sh {blue|green}-dap`.'
    exit 1
fi

lib_path=../bootstrap/workflow/aws/lib
source $lib_path/profile-configuration.sh
source $lib_path/env.sh
echo "DaP ~ deleting stateful Spark resources tied to $cluster cluster in $REGION"

echo "WARNING: historical s3 data (delta bucket) and Spark images + charts will be erased."
read -p "Are you sure? Type YES to confirm or any character to skip and review next resource: "
if [[ $REPLY =~ ^YES$ ]]; then
    for repo in spark spark/cache; do
        aws ecr delete-repository --repository-name $cluster/$repo --force; done
    for bucket in delta charts; do
        aws s3 rb s3://$cluster-$REGION-$bucket-$ACCOUNT --force; done
fi

echo "WARNING: metastore volume will be erased."
read -p "Are you sure? Type YES to confirm or any character to cancel: "
if [[ $REPLY =~ ^YES$ ]]; then
    volume=$cluster-metastore-postgresql-0
    pg_volume_id=`aws ec2 describe-volumes \
        --filters Name=tag:Name,Values=$volume --query Volumes[*].VolumeId --output text`
    aws ec2 delete-volume --volume-id $pg_volume_id &&
        echo "ebs volume $volume deleted"
fi

