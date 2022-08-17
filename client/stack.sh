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

    geth.yaml)
        N=5
        last_tags=`curl -s https://api.github.com/repos/ethereum/go-ethereum/tags?per_page=$N`
        versions=`egrep -o '[0-9]+(\.[0-9]+){2}", "commit": { "sha": ".{8}' <<< $last_tags | 
            awk -F'"' '{print "("i++")",$1,$NF}'`
        echo "Last $N tags pattern-matching releases in go-ethereum repo:"
        echo "    VERSION  COMMIT"
        echo "$versions"
        echo "do your own checks (parsing assumptions are weak in crypto)"
        echo "-> https://github.com/ethereum/go-ethereum/releases"
        read -p "Enter the version to bootstrap - index from 0 to $((N-1)): "
        if [[ ! $REPLY =~ ^[0-$((N-1))]$ ]]; then
            echo "DaP ~ aborting: invalid version index"
            exit
        fi
        read version commit <<< `awk '$1=="('$REPLY')"{print $2,$3}' <<< "$versions"`
        echo "DaP ~ selected $version (commit $commit)"
        build=geth-alltools-linux-amd64-$version-$commit
        aws cloudformation deploy --capabilities CAPABILITY_IAM \
            --stack-name dap-geth --template-file geth.yaml \
            --parameter-overrides GethBuild=$build ${@:2};;

    network.yaml)
        region=`aws configure get region`
        echo "Do you then intend to deploy Geth and/or DaP in $region region?"
        read -p "Press enter to confirm or any character to cancel: "
        if [[ ! $REPLY =~ ^$ ]]; then
            echo "DaP ~ canceled network creation"
            echo "see requirements (0.) in bootstrap/README"
            exit
        fi
        aws cloudformation deploy --stack-name dap-network --template-file network.yaml;;

    domain.yaml)
        domain=$2
        hz=`hosted_zone $domain`
        region=`aws configure get region`
        echo "DaP ~ creating/updating Cognito pool in $region: $domain"
        aws cloudformation deploy --stack-name dap-domain --template-file domain.yaml \
            --parameter-overrides Domain=$domain HostedZoneId=$hz SecurityMode=OFF;;

    *) echo "$1 template is not supported";;

esac

