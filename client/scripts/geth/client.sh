#!/bin/bash

if ${NetRestrict}; then
    netrestrict=`curl https://ip-ranges.amazonaws.com/ip-ranges.json |
        grep -Po '(?<="ip_prefix": ")(\d{1,3}\.){3}\d{1,3}/\d{1,2}' |
        paste -sd,`
else netrestrict=0.0.0.0/0; fi

client=/mnt/data/${Build}/geth
# necessary when executable has been pulled from backup
chmod +x $client

$client \
    --${Network} \
    --datadir /mnt/data/${Network} \
    --datadir.ancient /mnt/freezer/${Network} \
    --http \
    --http.api eth \
    --http.addr 0.0.0.0 \
    --ws \
    --ws.api eth \
    --ws.addr 0.0.0.0 \
    --netrestrict $netrestrict \
    --metrics \
    --pprof \
    --pprof.addr 0.0.0.0 \
    --authrpc.vhosts '*' \
    --authrpc.jwtsecret /jwt.hex \
    --authrpc.addr 0.0.0.0

