#!/bin/bash
set -eux
exec >> /var/log/bootstrap.log 2>&1

path=/mnt/data/prysm
mkdir -p $path
cd $path

set +e
[ -d dist ] && ls dist | grep -q ${Build}
if [ $? = 1 ]; then
    set -e
    version=`cut -d- -f1 <<< ${Build}`  # supports '$version' or '$version-modern' builds
    curl https://raw.githubusercontent.com/prysmaticlabs/prysm/master/prysm.sh \
        --output prysm.sh && chmod +x prysm.sh
    USE_PRYSM_MODERN=true USE_PRYSM_VERSION=$version ./prysm.sh beacon-chain --download-only
fi

