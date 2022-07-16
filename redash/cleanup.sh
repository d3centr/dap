#!/bin/bash

cluster=$1
if [ -z $cluster ]; then
    echo 'Cluster name argument is missing, e.g. run `./cleanup.sh {blue|green}-dap`.'
    exit 1
fi

lib_path=../bootstrap/workflow/aws/lib
source $lib_path/profile-configuration.sh
source $lib_path/env.sh
echo "DaP ~ deleting stateful Redash resources tied to $cluster cluster in $REGION"

echo "WARNING: Redash dashboards and charts will be erased."
read -p "Are you sure? Type YES to confirm or any character to exit: "

if [[ $REPLY =~ ^YES$ ]]; then

    volume=$cluster-redash-postgresql-0
    pg_volume_id=`aws ec2 describe-volumes \
        --filters Name=tag:Name,Values=$volume --query Volumes[*].VolumeId --output text`

    aws ec2 delete-volume --volume-id $pg_volume_id &&
        echo "ebs volume $volume deleted"

fi

