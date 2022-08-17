#!/bin/bash
source init.sh

profile=default
while (( $# )); do
    case $1 in
        -p|--profile) shift; profile=$1;;
        -*) echo "unknown $1 option" >&2; exit 1;;
    esac
    shift
done

argocd app create airflow \
    --upsert \
    --repo $DaP_REPO \
    --revision $DaP_BRANCH \
    --path airflow \
    --dest-namespace airflow \
    --dest-server https://kubernetes.default.svc \
    --sync-policy $DaP_SYNC \
    --self-heal \
    --auto-prune \
    --values profile/default.yaml \
    --values profile/$profile.yaml \
    -p region=$REGION \
    -p airflow.webserverSecretKey=`openssl rand -hex 16` \
    -p airflow.defaultAirflowRepository=$REGISTRY/airflow \
    -p airflow.dags.gitSync.repo=$DaP_REPO \
    -p airflow.dags.gitSync.branch=$DaP_BRANCH \
    -p airflow.config.logging.remote_base_log_folder=s3://$CLUSTER-$REGION-airflow-$ACCOUNT \
    -p airflow.postgresql.persistence.existingClaim=$PG_VOLUME

