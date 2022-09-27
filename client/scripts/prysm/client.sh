#!/bin/bash

client=/mnt/data/prysm/dist/beacon-chain-${Build}-linux-amd64
chmod +x $client

$client \
    --${Network} \
    --execution-endpoint=http://${Endpoint}:8551 \
    --jwt-secret=/jwt.hex \
    --datadir /mnt/data/${Network} \
    --monitoring-host 0.0.0.0 \
    --accept-terms-of-use

