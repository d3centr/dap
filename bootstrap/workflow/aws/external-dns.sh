#!/bin/bash
set -euo pipefail
#
# Manual run from bootstrap folder:
# . runtime.sh
# run_workflow . workflow/aws/lib/env.sh\; workflow/aws/external-dns.sh policy blue
# OR
# run_workflow . workflow/aws/lib/env.sh\; workflow/aws/external-dns.sh chart blue
source ../DaP/load_ENV.sh
: ${DaP_DOMAIN:=`env_path $DaP_ENV/cluster/INGRESS/DOMAIN`}
: ${DaP_PRIVATE_ZONE:=`env_path $DaP_ENV/cluster/INGRESS/PRIVATE_ZONE`}
: ${DaP_EXTERNAL_DNS:=`env_path $DaP_ENV/version/EXTERNAL_DNS`}

color=$2
case $1 in

    policy)
        # export zone_id to interpolate in policy
        export zone_id=$(aws route53 list-hosted-zones \
            --query 'HostedZones[?Config.PrivateZone==`'$DaP_PRIVATE_ZONE'` && Name==`'$DaP_DOMAIN'.`].Id' \
            --output text | sed 's/^\/hostedzone\///')

        envsubst < workflow/aws/iam/external-dns-policy.json |
            aws iam create-policy --policy-name $color-dap-dns-$REGION \
                --policy-document file:///dev/stdin;;

    chart)
        aws eks update-kubeconfig --name $color-dap

        zone_type=`$DaP_PRIVATE_ZONE && echo private || echo public`
        helm install \
            --namespace kube-system \
            --set domain=$DaP_DOMAIN,zoneType=$zone_type \
            --set ownerReference=$color-dap-$REGION \
            --set version=$DaP_EXTERNAL_DNS \
            external-dns ./workflow/aws/helm/external-dns;;

esac

