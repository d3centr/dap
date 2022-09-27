#!/bin/bash
source init.sh

path=${DaP_PATH:=.}
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
params="
global.profile=$profile
global.appVersion=$APP_VERSION
global.registry=$REGISTRY/spark
global.kanikoVersion=$DaP_KANIKO
build.repo=$DaP_REPO
build.branch=$DaP_BRANCH
build.path=$path
build.sparkVersion=$SPARK_VERSION
global.spark_version=v`tr . _ <<< $SPARK_VERSION`
global.scalaVersion=$SCALA_VERSION
postgresql.persistence.existingClaim=$PG_VOLUME
config=$config
"
params=`for p in $params; do printf -- "-p$p "; done`
if [ $app = sparkubi ]; then
    # extra parameters to build dapp artifacts (installer & helm charts)
    params="
        -pargocd=${DaP_ARGO_CD:=`env_path $DaP_ENV/version/ARGO_CD`}
        -pawscli=${DaP_AWSCLI:=`env_path $DaP_ENV/version/AWSCLI`}
        -pdebian=${DaP_DEBIAN:=`env_path $DaP_ENV/tag/DEBIAN`}
        -peksctl=${DaP_EKSCTL:=`env_path $DaP_ENV/version/EKSCTL`}
        -phelm=${DaP_HELM:=`env_path $DaP_ENV/version/HELM`}
        -pkubectl=${DaP_KUBECTL:=`env_path $DaP_ENV/version/KUBECTL`}
        -pchartmuseum.env.open.STORAGE_AMAZON_BUCKET=$CLUSTER-$REGION-charts-$ACCOUNT
        -pchartmuseum.env.open.STORAGE_AMAZON_REGION=$REGION
        $params
    "
fi

set -x
argocd app create $app \
    --upsert \
    --values values.yaml \
    --repo $DaP_REPO \
    --revision $DaP_BRANCH \
    --dest-namespace spark \
    --dest-server https://kubernetes.default.svc \
    --sync-policy $DaP_SYNC \
    --path $path/spark/$app \
    `[ $DaP_SYNC != none ] && echo --auto-prune --self-heal` \
    $params

