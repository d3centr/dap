#!/bin/bash
source ../bootstrap/app-init.sh
ETH_IP=`kubectl get cm env -n monitor -o "jsonpath={.data['ETHEREUM_IP']}"`

LIGHTHOUSE_IP=`aws cloudformation list-exports --output text \
    --query "Exports[?Name=='dap-network-lighthouse-ip'].Value"`

PRYSM_IP=`aws cloudformation list-exports --output text \
    --query "Exports[?Name=='dap-network-prysm-ip'].Value"`

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
    -p lighthouseIp=$LIGHTHOUSE_IP \
    -p prysmIp=$PRYSM_IP \
    --helm-set-file grafana.dashboards.default.kubernetes.json=dashboards/kubernetes.json \
    --helm-set-file grafana.dashboards.default.spark.json=dashboards/spark.json \
    --helm-set-file grafana.dashboards.client.geth.json=dashboards/client/geth.json \
    --helm-set-file grafana.dashboards.client.lighthouse.json=dashboards/client/lighthouse.json \
    --helm-set-file grafana.dashboards.client.prysm.json=dashboards/client/prysm.json

