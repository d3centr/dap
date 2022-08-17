from dap.events.etl import (
    data_sources, lookahead, process_batch, data_templates, job
)
from dap.events.dag import (
    scan_factory, shard_partitioner, block_partitioner, 
    partitioner_input, get_shard
)
from test.dap.events.constants import (
    FACTORY_SRC, DATA_SOURCES, 
    FACTORY_EVENTS, processed_FACTORY_EVENTS, 
    rendered_TEMPLATES
)
from dap.checkpoint import initialize_epoch
from dap.utils import eth_ip
from dap.job import get_meta
from test.dapp.uniswap.constants import TEMPLATE_DATA
from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
from web3 import Web3
from web3._utils.events import get_event_data
import os
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import s3fs
import boto3
import json
from hexbytes import HexBytes

PARAMS = {
    'dapp': 'uniswap',
    'path': 'test/dap/uniswap',
    'bucket': os.environ['TEST_BUCKET'],
    'eth_client': os.environ['ETHEREUM_CLIENT'],
    'epoch': 412
}
CONTRACT_COUNT_412 = 690

def dapp():
    return get_current_context()['dag_run'].conf['dapp']

@task()
def data_sources_test():
    actual = data_sources(dapp())
    expected = DATA_SOURCES
    assert(actual == expected)

@task(pool=PARAMS['eth_client'], pool_slots=1)
def lookahead_test():
    conf = get_current_context()['dag_run'].conf
    actual = lookahead(412, FACTORY_SRC, 'PoolCreated', conf)[:2]
    expected = FACTORY_EVENTS
    assert(actual == expected)

@task()
def process_batch_test():
    actual = process_batch(FACTORY_EVENTS)
    expected = processed_FACTORY_EVENTS
    assert(actual == expected)

@task()
def data_templates_test():
    actual = data_templates(dapp(), TEMPLATE_DATA)
    expected = rendered_TEMPLATES
    assert(actual == expected)

THREAD_INDEX = 0
@task()
def clear_output_paths(bucket, path, epoch, **params):
    s3 = boto3.resource('s3')
    for contract in ['Factory', 'NonfungiblePositionManager', 'Pool']:
        key = f'{path}/contract={contract}/epoch={epoch}/{THREAD_INDEX}.parquet.snappy'
        if s3fs.S3FileSystem().exists(f'{bucket}/{key}'):
            s3.Object(bucket, key).delete()
@task(pool=PARAMS['eth_client'], pool_slots=1)
def job_wrapper(epoch, dapp, path , bucket, eth_client):
    conf = {
        'dapp': dapp,
        'path': path,
        'bucket': bucket,
        'eth_client': eth_client
    }
    job(DATA_SOURCES + rendered_TEMPLATES, 
        THREAD_INDEX, epoch, conf, 'shard', early_stop=True)

@task()
def job_check():
    conf = get_current_context()['dag_run'].conf

    actual = pq.ParquetDataset(
        f"{conf['bucket']}/{conf['path']}",
        filesystem=s3fs.S3FileSystem()
    ).read().to_pandas()
    # normalize higer-level type of returned partitions
    actual['contract'] = actual.contract.astype(object)
    actual['epoch'] = actual.epoch.astype(np.int64)
    # turn hashes into hexadecimal as stored in csv extract 
    actual['blockHash'] = actual.blockHash.apply(bytes.hex)
    actual['transactionHash'] = actual.transactionHash.apply(bytes.hex)

    # if extract must be modified, e.g. due to repartitioning:
    # - load actual in a python shell and call df.to_csv(path, index=False)
    # - early_stop on epoch 412 in job wrapper yields 41 events (42 line csv)
    expected = pd.read_csv('dags/test/dap/events/events.csv')
    pd.testing.assert_frame_equal(actual, expected)

@task()
def scanned_contracts_check(args):
    assert(sorted(args.keys()) == [
        'epoch', 'last_block', 'sources', 'sources_dt'])
    conf = get_current_context()['dag_run'].conf
    sources = get_meta(conf['bucket'], conf['path'],
        f"{args['epoch']}_sources", args['sources_dt'])
    assert(len(sources) == CONTRACT_COUNT_412)
    for source in DATA_SOURCES + rendered_TEMPLATES:
        assert(source in sources)
    return args

SHARDS = 8
@task()
def shard_partitioner_check(args):
    assert(sorted(args.keys()) == [
        'epoch', 'last_block', 'sources', 'sources_dt', 'threads_dt'])
    epoch, bucket, path, sources = partitioner_input(args)
    threads = get_meta(bucket, path, f'{epoch}_threads', args['threads_dt'])
    assert(len(threads) == SHARDS)
    flat_threads = [source for thread in threads for source in thread]
    for source in sources:
        assert(source in flat_threads)
    assert(len(flat_threads) == CONTRACT_COUNT_412)
    distribution = [len(thread) for thread in threads]
    assert(distribution == [104, 88, 70, 86, 95, 84, 81, 82])

@task()
def block_partitioner_check(args):
    assert(sorted(args.keys()) == [
        'epoch', 'last_block', 'sources', 'sources_dt'])

@task()
def block_shard_test(args):
    epoch, bucket, path, sources = partitioner_input(args)
    # large index should not be used (would fail out-of-bounds)
    actual = get_shard(bucket, path, epoch, 'block', args, 9999)
    assert(actual == sources)

@task()
def get_shards_test(args):
    conf = get_current_context()['dag_run'].conf
    epoch, bucket, path = args['epoch'], conf['bucket'], conf['path']
    threads = get_meta(bucket, path, f'{epoch}_threads', args['threads_dt'])
    actual = []
    for i in range(SHARDS):
        actual.append(
            get_shard(bucket, path, epoch, 'shard', args, i)
        )
    assert(actual == threads)

@task(pool=PARAMS['eth_client'], pool_slots=1)
def inclusive_block_range():
    EVENT = 'PoolCreated'
    source = FACTORY_SRC

    eth_client = get_current_context()['dag_run'].conf['eth_client']
    w3 = Web3(Web3.WebsocketProvider(
        f"ws://{eth_ip(eth_client)}:8546", websocket_timeout=60))
    with open(f"dags/dapp/uniswap/{source['abi']}") as file:
        abi = json.load(file)
    contract = w3.eth.contract(address=source['address'], abi=abi)

    # assuming very first two created pools only in event sample
    assert(len(FACTORY_EVENTS) == 2)
    assert(FACTORY_EVENTS[0].transactionHash == HexBytes(
        '0x37d8f4b1b371fde9e4b1942588d16a1cbf424b7c66e731ec915aca785ca2efcf'))
    assert(FACTORY_EVENTS[1].transactionHash == HexBytes(
        '0xa877e18bbdcf69b751f56b4aa5b91a903ae69de2d775f1eb27fba4ba25abff2a'))
    firstPoolCreated, secondPoolCreated = 12369739, 12369760

    print('DaP ~ contract api test')
    events = contract.events[EVENT].createFilter(
        fromBlock = firstPoolCreated,
        toBlock = secondPoolCreated
    ).get_all_entries()
    assert(events == FACTORY_EVENTS)

    print('DaP ~ log api test')
    signature = 'PoolCreated(address,address,uint24,int24,address)'
    logs = w3.eth.get_logs({
        'address': source['address'],
        'fromBlock': firstPoolCreated,
        'toBlock': secondPoolCreated,
        'topics': [[Web3.keccak(text=signature).hex()]]
    })
    event_abi = [e for e in abi if e['name'] == EVENT][0]
    events = [get_event_data(w3.codec, event_abi, log) for log in logs]
    assert(events == FACTORY_EVENTS)

@dag(
    schedule_interval=None,
    start_date=days_ago(2),
    params=PARAMS,
    tags=['test', 'dap'],
    render_template_as_native_obj=True
)
def dap_Event_ok():
    data_sources_test()
    lookahead_test()
    process_batch_test()
    data_templates_test()
    inclusive_block_range()

    clear_output_paths(
        **PARAMS
    ) >> job_wrapper(
        **PARAMS
    ) >> job_check()

    contracts = scanned_contracts_check(
        scan_factory(PARAMS['eth_client'])(
            initialize_epoch(bucket='{{ params.bucket }}')
        )
    )
    shard_partitions = shard_partitioner(contracts, SHARDS)
    block_partitions = block_partitioner(contracts)
    shard_partitioner_check(shard_partitions)
    block_partitioner_check(block_partitions)
    block_shard_test(block_partitions)
    get_shards_test(shard_partitions)

test_dag = dap_Event_ok()

