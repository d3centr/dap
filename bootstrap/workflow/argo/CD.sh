#!/bin/bash
set -euo pipefail
#
# Manual run from bootstrap folder:
# . runtime.sh
# run_workflow . workflow/aws/lib/env.sh --dns\; workflow/argo/CD.sh blue
source ../DaP/load_ENV.sh
: ${DaP_REPO:=`env_path $DaP_ENV/REPO`}
: ${DaP_SSH_KEY_NAME:=`env_path $DaP_ENV/REPO/SSH_KEY_NAME`}
: ${DaP_INGRESS:=`env_path $DaP_ENV/cluster/INGRESS`}

color=$1
aws eks update-kubeconfig --name $color-dap

export DaP_ARGO_CD=${DaP_ARGO_CD:=`env_path $DaP_ENV/version/ARGO_CD`}
# added bootstrap/**/argo/kustomization.yaml to .gitignore
envsubst < workflow/argo/tpl.kustomization.yaml > workflow/argo/kustomization.yaml
kubectl apply -k workflow/argo

# assuming that any repo not using the https protocol is a ssh url
grep -qv '^https://' <<< $DaP_REPO && [ -f /root/.dap/$DaP_SSH_KEY_NAME ] &&
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: $DaP_REPO
  sshPrivateKey: |
`sed 's/^/    /' /root/.dap/$DaP_SSH_KEY_NAME`
EOF

if $DaP_INGRESS; then 
    DaP_ingress $color/argocd/argocd-server/80 cd; fi

