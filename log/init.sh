#!/bin/bash
source ../bootstrap/app-init.sh

# export to interpolate in install envsubst
export LOG_BUCKET=`kubectl get cm env -o "jsonpath={.data['LOG_BUCKET']}"`

