#!/bin/bash
set -eux
exec >> /var/log/bootstrap.log 2>&1

binary=/mnt/data/lighthouse
# check if version is already installed to speed up reboot
[ -f $binary ] && grep -q `$binary --version |
    egrep -o 'v[0-9]+(\.[0-9]+){2}'` <<< ${Build}
if [ $? = 1 ]; then

    curl -L ${Build} -o lighthouse.tar.gz
    curl -L ${Build}.asc -o lighthouse.tar.gz.asc

    gpg --keyserver hkp://keyserver.ubuntu.com \
        --recv-keys 15E66D941F697E28F49381F426416DC3F30674B0
    gpg --verify lighthouse.tar.gz.asc

    tar xzf lighthouse.tar.gz -C /mnt/data

fi

