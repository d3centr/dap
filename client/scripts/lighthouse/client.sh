#!/bin/bash

/mnt/data/lighthouse beacon \
    --network ${Network} \
    --target-peers 80 \
    --disable-upnp \
    --execution-endpoint http://${Endpoint}:8551 \
    --execution-jwt /jwt.hex \
    --datadir /mnt/data/${Network} \
    --freezer-dir /mnt/freezer/${Network} \
    --metrics \
    --metrics-address 0.0.0.0

