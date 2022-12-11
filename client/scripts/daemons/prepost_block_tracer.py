#!/opt/pyd/bin/python

import os
import os.path
import time
from systemd import journal
from web3 import Web3
from multiprocessing import Pool
import math
import traceback as tb
import pprint
from datetime import datetime
import boto3

THREADS = 2
ERC20_TRANSFER = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
ERC721_TRANSFER = '0x9d9af8e38d66c62e2c12f0225249fd9d721c54b83f48d9352c97c6cacdcb6f31'
MAX_TRACED_LOGS = 10
TIMEOUT = 10
BUCKET = os.environ['SINK_BUCKET']
AWS_REGION = os.environ['AWS_REGION']

start = time.time()
checkpoint_folder = f'/tmp/prepost-block-tracer-{start}'
os.mkdir(checkpoint_folder)
checkpoint = checkpoint_folder + '/checkpoint'

w3 = Web3(Web3.IPCProvider('/mnt/data/mainnet/geth.ipc'))

def trace_tx(tx):
    t0 = time.time()
    ipc = Web3.IPCProvider('/mnt/data/mainnet/geth.ipc', TIMEOUT)
    w3 = Web3(ipc)
    tx_hash = tx.hash.hex()
    tx = dict(tx)
    receipt = w3.eth.getTransactionReceipt(tx_hash)
    log_count = len(receipt.logs)
    erc721_txs = sum(l.topics[0].hex() == ERC721_TRANSFER for l in receipt.logs)
    # turn AttributeDict types to plain serializable dict
    receipt = dict(receipt, logs=[dict(log) for log in receipt.logs
        if log.topics[0].hex() == ERC20_TRANSFER])
    erc20_txs = len(receipt['logs'])

    # last condition excludes tracing of NFT aggregators
    if log_count <= MAX_TRACED_LOGS and erc20_txs > 0 and erc721_txs < 2:

        try:
            # IMPORTANT:
            # debug_traceCall runs an eth_call in the given block execution
            # using the final state of parent block as the base,
            # i.e. as if the transaction ran first in the block.
            tx_trace = ipc.make_request('debug_traceCall', [{
                'from': tx['from'], 'to': tx['to'],
                'gas': hex(tx['gas']), 'data': tx['input']
            }, hex(tx['blockNumber']), {
                'disableStorage': False, 'disableMemory': False
                }])  # TODO: review perf. risk to miss logs when above disabled
            if 'error' in tx_trace.keys():
                journal.write(tx_trace['error'])
                raise Exception
            # according to the Yellow paper documentation of LOG opcodes:
            # third stack element is the first topic (reversed order in trace)
            transfers = [op for op in tx_trace['result']['structLogs']
                if op['op'] == 'LOG3' and op['stack'][-3] == ERC20_TRANSFER]
            tx_trace.update({
                'tx': tx,
                'receipt': receipt,
                'structLogs': transfers,
                'traced': 1
            })
            duration = f'{math.ceil(time.time() - t0)}s'
        except Exception as e:
            journal.write(''.join(tb.format_exception(type(e), e, e.__traceback__)))
            journal.write(f'{tx_hash} tracing failed w/ {log_count} initial logs')
            return {
                'tx': tx, 'receipt': receipt, 'structLogs': [], 'traced': -1
            }

    else:

        duration = 'na'
        tx_trace = {
            'tx': tx, 'receipt': receipt, 'structLogs': [], 'traced': 0
        }

    # journal.write(f'traced {tx_hash} in {duration} '
    #     f'w/ {erc20_txs} transfer(s) & {log_count} initial logs')

    return tx_trace

while True:

    while w3.eth.syncing:
        journal.write('paused tracing: client is syncing')
        time.sleep(30)

    start = time.time()

    last_block = w3.eth.block_number
    finalized_block = last_block - 64
    tracing_limit = last_block - 100
    if os.path.isfile(checkpoint):
        with open(checkpoint) as c:
            index = max(int(c.read()) + 1, tracing_limit)
        if index > finalized_block:
            journal.write(f'block index {index} not finalized at {start}')
            time.sleep(1)
            continue
    else:
        index = finalized_block
    block = w3.eth.get_block(index, full_transactions=True)

    with Pool(THREADS) as pool:
        traces = pool.map(trace_tx, block.transactions)
    assert(len(traces) == len(block.transactions))

    i = 0
    for tx in traces:
        receipt_logs = tx['receipt']['logs']
        if receipt_logs:
            break
        else:
            i += 1
    journal.write('First filtered LOGS:')
    journal.write(pprint.pformat(receipt_logs))
    journal.write('First filtered TRACES:')
    journal.write(pprint.pformat(traces[i]['structLogs']))

    date = datetime.utcfromtimestamp(block.timestamp).strftime('%Y-%m-%d')
    key = f'data/{AWS_REGION}/traces/prepost/date={date}/{index}.json'
    boto3.resource('s3').Object(BUCKET, key).put(Body=Web3.toJSON(traces))

    with open(checkpoint, 'w') as c:
        c.write(str(index))

    journal.write(f'block {index} took {round(time.time() - start, 1)}s '
        f'at finality index {finalized_block - index}: '
        f"{sum(t['traced'] == -1 for t in traces)} failed trace(s)")

