#!/bin/bash

cluster=$1
if [ -z $cluster ]; then 
    echo 'Cluster name argument is missing, e.g. run `./cleanup.sh {blue|green}-dap`.'
    exit 1
fi

lib_path=../bootstrap/workflow/aws/lib
source $lib_path/profile-configuration.sh
source $lib_path/env.sh
echo "DaP ~ deleting stateful Airflow resources tied to $cluster cluster in $REGION"

echo "WARNING: historical s3 data, container images and dag run records will be erased." 
read -p "Are you sure? Type YES to confirm or any character to exit: "

if [[ $REPLY =~ ^YES$ ]]; then

    airflow_bucket=$cluster-$REGION-airflow-$ACCOUNT
    data_bucket=$cluster-$REGION-data-$ACCOUNT
    pg_volume=$cluster-airflow-postgresql-0
    pg_volume_id=`aws ec2 describe-volumes \
        --filters Name=tag:Name,Values=$pg_volume --query Volumes[*].VolumeId --output text`
    
    aws ecr delete-repository --repository-name $cluster/airflow --force
    aws ecr delete-repository --repository-name $cluster/airflow/cache --force
    aws s3 rb s3://$airflow_bucket --force
    aws s3 rb s3://$data_bucket --force
    aws ec2 delete-volume --volume-id $pg_volume_id
    echo "ebs volume $pg_volume deleted"

fi

