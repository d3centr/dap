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

argocd app create superset \
    --upsert \
    --repo $DaP_REPO \
    --revision $DaP_BRANCH \
    --path superset \
    --dest-namespace superset \
    --dest-server https://kubernetes.default.svc \
    --sync-policy $DaP_SYNC \
    --self-heal \
    --auto-prune \
    --values profile/default.yaml \
    --values profile/$profile.yaml \
    --values values.yaml \
    -p superset.image.repository=$REGISTRY/superset \
    -p superset.postgresql.primary.persistence.existingClaim=$PG_VOLUME

