#!/bin/bash

help () { echo "
    usage: ./install.sh -a <superset|airflow|spark> [-p <profile>]

    -a|--app) DaP application:
        'superset' to install dashboards;
        'spark' to build data processing applications;
        'airflow' only supported with '--profile keys',
            a pipeline's Airflow dags are integrated with the app build.

    -c|--confirm) do not prompt for confirmation

    -p|--profile) optional, installation profile:
        'hot' to skip redundant setup of first cluster install;
        'keys' to only create SSH key secrets of pipeline repositories.
";}

make_secrets () {
    for key in `ls ~/.dap/pipeline/*.pem`; do
        dapp=`awk -F[/.] '{print $(NF-1)}' <<< $key`
        cat <<-EOF | kubectl apply -f -
	apiVersion: v1
	kind: Secret
	metadata:
	  name: $dapp-deploy-key
	  namespace: $app
	stringData:
	  key: |
	`sed 's/^/            /' $key`
	EOF
    done
}

profile=default
confirm=true
while (( $# )); do
    case $1 in
        -a|--app) shift; app=${1///};;
        -c|--confirm) confirm=false;;
        -h|--help) help; exit;;
        -p|--profile) shift; profile=$1;;
        -*) echo "unknown $1 option" >&2; help; exit 1;;
    esac
    shift
done
# source app-init only here to allow help display when no cluster
. ../bootstrap/app-init.sh

if [ $profile = keys ]; then
    echo "only creating SSH secrets from ~/.dap/pipeline/*.pem keys in $app namespace"
    make_secrets
    exit 0
fi

parameter_file=`env_file $DaP_ENV/dapps`
echo "DaP ~ $app artefacts will be installed on `kubectl config current-context`"
echo "DaP ~ sourcing params from $parameter_file: see all dapps including $app in apps"
cat $parameter_file
if $confirm; then
    read -p "Press enter to confirm or any character to cancel: "
    if [[ ! $REPLY =~ ^$ ]]; then echo "DaP ~ canceled pipeline installation"; exit 1; fi
fi

[ $profile != hot ] && {
# see https://github.com/argoproj/argo-workflows/blob/master/docs/workflow-rbac.md
export EXEC_RULES='
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
    envsubst < $app/template.yaml | kubectl apply -f -
    make_secrets
    [ $app = spark ] && {

        eksctl create iamserviceaccount \
            --name spark-dapp-installer \
            --namespace spark \
            --cluster $CLUSTER \
            --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
            --attach-policy-arn arn:aws:iam::$ACCOUNT:policy/$CLUSTER-installer-$REGION \
            --approve \
            --override-existing-serviceaccounts

        # successful parsing requires that 'dapp' key is always defined before 'repo' key
        set -- `egrep '(dapp: |repo: .*@)' $parameter_file | awk '{print $NF}'`
        while (( $# )); do
            case $1 in
                *@*) argocd repo add $1 --insecure-skip-server-verification \
                         --ssh-private-key-path ~/.dap/pipeline/$dapp.pem;;
                *) dapp=$1;;
            esac
            shift
        done

    }
}

argo submit $app/installer.yaml \
  --serviceaccount $app-dapp-installer \
  --parameter-file $parameter_file \
  -p registry=$REGISTRY \
  -p kubectl=${DaP_KUBECTL:=`env_path $DaP_ENV/version/KUBECTL`} \
  -n $app --watch

