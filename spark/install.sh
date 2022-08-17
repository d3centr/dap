#!/bin/bash
source init.sh

profile=default
config=default
while (( $# )); do
    case $1 in
        -a|--app) shift; app=${1///};;
        -c|--config) shift; config=$1;;
        -p|--profile) shift; profile=$1;;
        -*) echo "unknown $1 option" >&2; exit 1;;
    esac
    shift
done

. $app/config/VERSIONS
p0="global.appVersion=$APP_VERSION"
p1="global.registry=$REGISTRY/spark"
p2="build.repo=$DaP_REPO"
p3="build.branch=$DaP_BRANCH"
p4="build.sparkVersion=$SPARK_VERSION"
p5="build.scalaVersion=$SCALA_VERSION"
p6="postgresql.persistence.existingClaim=$PG_VOLUME"
p7="config=$config"

argocd app create $app \
    --upsert \
    --repo $DaP_REPO \
    --revision $DaP_BRANCH \
    --path spark/$app \
    --dest-namespace spark \
    --dest-server https://kubernetes.default.svc \
    --sync-policy $DaP_SYNC \
    --self-heal \
    --auto-prune \
    --config-management-plugin kustomized-helm \
    --plugin-env HELM_VALUES="
        ../charts/profile/$SPARK_VERSION.yaml 
        ../charts/profile/default.yaml 
        ../charts/profile/$profile.yaml 
        values.yaml" \
    --plugin-env DYNAMIC_VAR=$p0,$p1,$p2,$p3,$p4,$p5,$p6,$p7

# --set $DYNAMIC_VAR added to helm plugin command in argocd-cm
# similarly for ordered $HELM_VALUES

