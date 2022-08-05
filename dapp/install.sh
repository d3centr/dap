#!/bin/bash
set -eu

help () { echo "
    usage: ./install.sh -a <superset|airflow|spark> -d <dapp> [-p <profile>]

    -a|--app) DaP application, one of dap/dapp subfolders:
        'superset' to install dashboards;
        'spark' to build a data processing application;
        'airflow' to deploy DAGs

    -c|--confirm) do not prompt for confirmation

    -d|--dapp) 'name' of a DaP pipeline (DaPp):
        refers to a configuration file under DaP/<ENV>/dapp/ path;
        and to the deploy key under ~/.dap/ when repo is private,
        e.g. when pipeline configuration is under DaP/live/dapp/uniswap;
            -d argument is 'uniswap' and SSH key ~/.dap/uniswap authenticates

    -p|--profile) optional, installation profile:
        'hot' to skip redundant setup of first cluster install
";}

profile=default
confirm=true
while (( $# )); do
    case $1 in
        -a|--app) shift; app=${1///};;
        -c|--confirm) confirm=false;;
        -d|--dapp) shift; dapp=$1;;
        -h|--help) help; exit;;
        -p|--profile) shift; profile=$1;;
        -*) echo "unknown $1 option" >&2; help; exit 1;;
    esac
    shift
done

source ../DaP/load_ENV.sh
parameter_file=`env_file $DaP_ENV/dapp/$dapp`
if $confirm; then
    echo
    echo "DaP ~ $dapp ($app) will be installed on `kubectl config current-context`"
    echo "DaP ~ sourcing parameters from $parameter_file"
    cat $parameter_file
    read -p "Press enter to confirm or any character to cancel: "
    if [[ ! $REPLY =~ ^$ ]]; then echo "DaP ~ canceled pipeline installation"; exit 1; fi
fi

[ $profile != hot ] && {
# see https://github.com/argoproj/argo-workflows/blob/master/docs/workflow-rbac.md
export exec_rules='
  - apiGroups:
      - argoproj.io
    resources:
      - workflowtaskresults
    verbs:
      - create
      - patch
  # for <= v3.3 only
  - apiGroups:
      - ""
    resources:
      - pods
    verbs:
      - get
      - patch
'

    envsubst < $app/tpl.sa.yaml | kubectl apply -f -

    [ -f ~/.dap/$dapp ] &&
        cat <<-EOF | kubectl apply -f -
	apiVersion: v1
	kind: Secret
	metadata:
	  name: $dapp-deploy-key
	  namespace: $app
	stringData:
	  key: |
	`sed 's/^/            /' ~/.dap/$dapp`
	EOF

}

argo submit $app/installer.yaml \
  --serviceaccount $app-dapp-installer \
  --parameter-file $parameter_file \
  -p dapp=$dapp \
  -p kubectl=${DaP_KUBECTL:=`env_path $DaP_ENV/version/KUBECTL`}

echo "run \"dap argo wait -n $app <Workflow Name>\" to return status on the cli"

