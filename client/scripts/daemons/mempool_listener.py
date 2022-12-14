#!/opt/pyd/bin/python

import os
from time import time
from systemd import journal
import asyncio
import json
import websockets
import boto3
from copy import deepcopy

BUCKET = os.environ['SINK_BUCKET']
REGION = os.environ['AWS_REGION']

async def put_txs(records, bucket=BUCKET, region=REGION):
    if records:
        log = '\n'.join(records)
        now = int(time())
        key = f'data/{region}/mempool/txs/{now}.json'
        boto3.resource('s3').Object(bucket, key).put(Body=log)
        journal.write(f'PUT {len(records)} records at {now}')

async def get_event():
    async with websockets.connect('ws://localhost:8546') as ws:
        await ws.send("""{
            "jsonrpc": "2.0",
            "id": 0,
            "method": "eth_subscribe",
            "params": ["newPendingTransactions"]
        }""")
        response = await ws.recv()
        journal.write(response)

        records, tasks, start_buffer = [], set(), time()
        while True:
            event = await ws.recv()
            ts = time()
            tx = json.loads(event)['params']['result']
            journal.write(f'GET {tx} at {ts}')
            record = '{"tx":"%s","ts":"%s"}' % (tx, ts)
            if len(records) < 10000 and time() - start_buffer < 120:
                records.append(record)
                journal.write(f'{len(records)} records in buffer')
            else:
                task = asyncio.create_task(put_txs(deepcopy(records)))
                tasks.add(task)
                task.add_done_callback(tasks.discard)
                journal.write(f'{len(tasks)} PUT tasks in queue')
                records, start_buffer = [], time()
                records.append(record)

if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    while True:
        loop.run_until_complete(get_event())

