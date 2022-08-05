#!/bin/bash
set -eo pipefail
. ../bootstrap/workflow/aws/lib/profile-configuration.sh

hosted_zone () {
    local domain=$1
    aws route53 list-hosted-zones \
        --query 'HostedZones[?Config.PrivateZone==`false` && Name==`'$domain'.`].Id' \
        --output text | sed 's/^\/hostedzone\///'
}

case $1 in

    network.yaml)
        region=`aws configure get region`
        echo "Do you intend to deploy Geth and/or DaP in $region region?"
        read -p "Press enter to confirm or any character to cancel: "
        if [[ ! $REPLY =~ ^$ ]]; then
            echo "DaP ~ canceled network creation"
            echo "see requirements (0.) in bootstrap/README"
            exit
        fi
        aws cloudformation create-stack --stack-name dap-network \
            --template-body file://network.yaml;;

    domain.yaml)
        domain=$2
        hz=`hosted_zone $domain`
        region=`aws configure get region`
        echo "DaP ~ creating/updating Cognito pool in $region: $domain"
        aws cloudformation deploy --stack-name dap-domain --template-file domain.yaml \
            --parameter-overrides Domain=$domain HostedZoneId=$hz SecurityMode=OFF;;

    *) echo "$1 template is not supported";;

esac

