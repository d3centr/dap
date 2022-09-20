#!/bin/bash
set -eux
exec >> /var/log/bootstrap.log 2>&1

if [ ! -d /mnt/data/${Build} ]; then
    BUILD_ARCHIVE=${Build}.tar.gz

    archive_link=https://gethstore.blob.core.windows.net/builds/$BUILD_ARCHIVE
    curl $archive_link -O
    curl $archive_link.asc -O

    gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 9BA28146
    gpg --verify $BUILD_ARCHIVE.asc

    tar xzf $BUILD_ARCHIVE -C /mnt/data
fi

