#!/bin/bash
set -eo pipefail
. ../bootstrap/workflow/aws/lib/profile-configuration.sh

hosted_zone () {
    local domain=$1
    aws route53 list-hosted-zones \
        --query 'HostedZones[?Config.PrivateZone==`false` && Name==`'$domain'.`].Id' \
        --output text | sed 's/^\/hostedzone\///'
}

upload_client_scripts () {
    local client=$1
    local region=`aws configure get region`
    local account=`aws sts get-caller-identity --query Account --output text`
    aws s3 cp scripts/$client/client.sh \
        s3://dap-$region-client-$account/scripts/$client/client.sh
    aws s3 cp scripts/$client/install.sh \
        s3://dap-$region-client-$account/scripts/$client/install.sh
}

generate_jwt () {
    local jwt_path=$1
    echo "generating Json Web Token $jwt_path if it does not exist"
    local jwt=`aws ssm describe-parameters --output text \
        --filters Key=Name,Values=$jwt_path`
    if [ -z "$jwt" ]; then
        aws ssm put-parameter --name $jwt_path --type String \
            --value `openssl rand -hex 32 | tr -d '\n'`
    fi
}

consensus_version () {
    local last_tags=$1
    # match last double quote to exclude release candidates
    local versions=`egrep -o 'name": "v[0-9]+(\.[0-9]+){2}"' <<< "$last_tags" |
        awk -F'"' '{print "("i++")",$(NF-1)}'`
    echo "$versions"
    n=`wc -l <<< "$versions"`  # filtered count
    read -p "Enter the version to install - index from 0 to $((n-1)): "
    if [[ ! $REPLY =~ ^[0-$((n-1))]$ ]]; then
        echo "DaP ~ aborting: invalid version index"
        exit
    fi
    version=`awk '$1=="('$REPLY')"{print $2}' <<< "$versions"`
    echo "DaP ~ selected $version"
}

case $1 in

    geth.yaml)
        N=5

        params=()
        beacon_client=prysm
        network=mainnet
        for param in ${@:2}; do
            IFS== read key value <<< "$param"
            if [ $key = BeaconClient ]; then
                beacon_client=$value
            elif [ $key = Network ]; then
                network=$value
                params+=( $key=$value )
            else
                params+=( $key=$value )
            fi
        done
        params+=( JsonWebToken=/cfn/dap/$beacon_client/$network/jwt )
        
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

        upload_client_scripts geth
        build=geth-alltools-linux-amd64-$version-$commit
        aws cloudformation deploy --capabilities CAPABILITY_IAM \
            --stack-name dap-geth-mainnet --template-file geth.yaml \
            --parameter-overrides Build=$build ${params[@]};;

    lighthouse.yaml)
        N=5
        echo "checking https://github.com/sigp/lighthouse/releases..."
        last_tags=`curl -s https://api.github.com/repos/sigp/lighthouse/tags?per_page=$N`

        consensus_version "$last_tags"
        upload_client_scripts lighthouse
        generate_jwt /cfn/dap/lighthouse/mainnet/jwt

        download=https://github.com/sigp/lighthouse/releases/download
        build=$download/$version/lighthouse-$version-x86_64-unknown-linux-gnu.tar.gz
        aws cloudformation deploy --capabilities CAPABILITY_IAM \
            --stack-name dap-lighthouse-mainnet --template-file lighthouse.yaml \
            --parameter-overrides Build=$build ${@:2};;

    prysm.yaml)
        N=10  # scan more tags than lighthouse to filter through release candidates
        echo "checking https://github.com/prysmaticlabs/prysm/releases..."
        last_tags=`curl -s https://api.github.com/repos/prysmaticlabs/prysm/tags?per_page=$N`

        consensus_version "$last_tags"
        upload_client_scripts prysm
        generate_jwt /cfn/dap/prysm/mainnet/jwt

        aws cloudformation deploy --capabilities CAPABILITY_IAM \
            --stack-name dap-prysm-mainnet --template-file prysm.yaml \
            --parameter-overrides Build=${version}-modern ${@:2};;

    network.yaml)
        region=`aws configure get region`
        echo "Do you then intend to deploy Ethereum clients and/or DaP in $region region?"
        read -p "Press enter to confirm or any character to cancel: "
        if [[ ! $REPLY =~ ^$ ]]; then
            echo "DaP ~ canceled network creation"
            echo "see requirements (0.) in bootstrap/README"
            exit
        fi
        aws cloudformation deploy --stack-name dap-network --template-file network.yaml
        account=`aws sts get-caller-identity --query Account --output text`
        aws s3 cp client.yaml s3://dap-$region-client-$account/templates/client.yaml;;

    domain.yaml)
        domain=$2
        hz=`hosted_zone $domain`
        region=`aws configure get region`
        echo "DaP ~ creating/updating Cognito pool in $region: $domain"
        aws cloudformation deploy --stack-name dap-domain --template-file domain.yaml \
            --parameter-overrides Domain=$domain HostedZoneId=$hz SecurityMode=OFF;;

    *) echo "$1 template is not supported";;

esac

