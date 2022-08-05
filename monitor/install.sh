#!/bin/bash
source ../bootstrap/app-init.sh
ETH_IP=`kubectl get cm env -n monitor -o "jsonpath={.data['ETHEREUM_IP']}"`

namespace=monitor
argocd app create $namespace \
    --upsert \
    --repo $DaP_REPO \
    --revision $DaP_BRANCH \
    --path $namespace \
    --dest-namespace $namespace \
    --dest-server https://kubernetes.default.svc \
    --sync-policy $DaP_SYNC \
    --self-heal \
    --auto-prune \
    -p ethIp=$ETH_IP \
    --helm-set-file grafana.dashboards.default.kubernetes.json=dashboards/kubernetes.json \
    --helm-set-file grafana.dashboards.default.spark.json=dashboards/spark.json \
    --helm-set-file grafana.dashboards.default.geth.json=dashboards/geth.json

