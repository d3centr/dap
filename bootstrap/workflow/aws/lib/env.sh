#!/bin/bash
# do not set shell options on a sourced script

echo "DaP ~ loading environment variables"

# --profile for safety: sourcing this script throws an error when profile hasn't been configured
region=`aws configure get region --profile $AWS_PROFILE`; return_code=$?
if [ $return_code -ne 0 ]; then
    case $return_code in 252)
        echo 'DaP ~ aborting: 252 error code suggests that you should export $AWS_PROFILE'
        echo 'you can source profile-configuration.sh to set a default profile';;
    esac
else
    export REGION=$region
    export ACCOUNT=`aws sts get-caller-identity --query Account --output text`
    
    if [ "$1" = --dns ]; then
        source ../DaP/load_ENV.sh
        export DaP_DOMAIN=${DaP_DOMAIN:=`env_path $DaP_ENV/cluster/INGRESS/DOMAIN`}
        echo "DaP ~ loading domain configuration in $REGION: $DaP_DOMAIN"

        cognito_ids=`aws cloudformation list-exports --output text \
            --query "Exports[?starts_with(Name, 'dap-domain-')].[Name, Value]"`
        export DaP_COGNITO_POOL=`awk '$1~/pool$/{print $2}' <<< "$cognito_ids"`
        export DaP_COGNITO_CLIENT=`awk '$1~/client$/{print $2}' <<< "$cognito_ids"`
        export DaP_CERTIFICATE=`awk '$1~/sub-cert$/{print $2}' <<< "$cognito_ids"`

        DaP_ingress () {
            local color namespace service port subdomain
            IFS=/ read color namespace service port <<< $1
            if [ $color = blue ]; then subdomain=$2; else subdomain=${2}2; fi
            helm upgrade -i --namespace $namespace \
                --set account=$ACCOUNT,region=$REGION \
                --set certificate=$DaP_CERTIFICATE \
                --set pool=$DaP_COGNITO_POOL,client=$DaP_COGNITO_CLIENT \
                --set service=$service,port=$port \
                --set subdomain=$subdomain,domain=$DaP_DOMAIN \
                ingress workflow/aws/helm/ingress
        }
        export -f DaP_ingress
    fi
fi

