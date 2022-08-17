from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
from airflow.api.client.local_client import Client
import os
import boto3
from web3 import Web3
import mmh3
from copy import deepcopy
from dap.utils import eth_ip, scale_pool, trigger
from dap.checkpoint import initialize_epoch, checkpoint_epoch
from dap.job import put_meta, get_meta
from dap.constants import EPOCH_LENGTH
from dap.events.etl import BATCH_LENGTH
import dap.events.etl as etl

def scan_factory(pool, slots=1):

    @task(pool=pool, pool_slots=slots)
    def scan_factory(args):
        conf = get_current_context()['dag_run'].conf
        dapp, path = conf['dapp'], conf['path']
        epoch, sources = args['epoch'], deepcopy(args['sources'])
    
        factories = __import__(f"dapp.{dapp}.factories", fromlist=['FACTORIES'])
        contracts = []
        for source in sources:
            if source['is_factory']:
                factory = factories.FACTORIES[source['name']]
                new_contracts = etl.lookahead(epoch, source, factory['event'], conf)
                batch = etl.process_batch(new_contracts)
                factory_path = f"{path}/contract={source['name']}"
                contracts += factory['handler'](
                    conf['bucket'], factory_path, epoch, batch)
        if contracts:
            sources += etl.data_templates(dapp, contracts)

        dt = put_meta(conf['bucket'], path, f'{epoch}_sources', sources)
        args.update({'sources_dt': dt})
        return args

    return scan_factory

def partitioner_input(args):
    conf = get_current_context()['dag_run'].conf
    epoch, bucket, path = args['epoch'], conf['bucket'], conf['path']
    sources = get_meta(bucket, path, f'{epoch}_sources', args['sources_dt'])
    return epoch, bucket, path, sources

@task()
def shard_partitioner(args, THREADS):
    epoch, bucket, path, sources = partitioner_input(args)
    THREADS = max(THREADS, 1)
    threads = [[] for _ in range(THREADS)]
    for source in sources:
        i = mmh3.hash(source['address'], signed=False) % THREADS
        threads[i].append(source)
    dt = put_meta(bucket, path, f'{epoch}_threads', threads)
    args.update({'threads_dt': dt})
    return args

@task()
def block_partitioner(args):
    # Placeholder to pass args to checkpoint task instead of shard partitioner.
    # Block partitioner does not shard data but split blocks in batches:
    # threads pull all sources.
    return args

def get_shard(bucket, path, epoch, partitioner, args, i):
    if partitioner == 'block':
        return get_meta(bucket, path,
            f'{epoch}_sources', args['sources_dt']
        )
    else:
        return get_meta(bucket, path, 
            f'{epoch}_threads', args['threads_dt']
        )[i]

def thread(pool, partitioner, slots=1):  # 10 pool slots  = 1 vCPU

    @task(pool=pool, pool_slots=slots)
    def thread(i, args):
        conf = get_current_context()['dag_run'].conf
        epoch, bucket, path = args['epoch'], conf['bucket'], conf['path']
        shard = get_shard(bucket, path, epoch, partitioner, args, i)
        etl.job(shard, i, epoch, conf, partitioner=partitioner)
        return args

    return thread

def dapp(dapp, 
    prefix, 
    shards=0,
    thread_deciCPU=2,
    dag_kwargs={
        'schedule_interval': None,
        'start_date': days_ago(2),
        'catchup': False,
        'default_args': {
            'retries': 1
        }
    },
    bucket=os.environ['DATA_BUCKET'], 
    eth_client=os.environ['ETHEREUM_CLIENT']):

    @dag(
        dag_id=f'{prefix}_Event', 
        params={
            'dapp': dapp, 
            'path': f'{dapp}/shards={shards}',
            'bucket': bucket,
            'eth_client': eth_client
        },
        tags=['job', prefix],
        max_active_runs=1,
        **dag_kwargs
    )
    def dap_Event():
        scanned_contracts = scan_factory(eth_client)(
            initialize_epoch('{{ params.bucket }}')
        )
        scale_pool('{{ params.eth_client }}') >> scanned_contracts
        if shards == 0:
            partitioner = 'block'
            assert(EPOCH_LENGTH % BATCH_LENGTH == 0)
            threads = EPOCH_LENGTH // BATCH_LENGTH
            args = block_partitioner(scanned_contracts)
        else:
            partitioner = 'shard'
            args = shard_partitioner(scanned_contracts, shards)
            threads = max(shards, 1)
        checkpoint_task = checkpoint_epoch(args)
        thread_task = thread(eth_client, partitioner, slots=thread_deciCPU)
        for i in range(threads):
            thread_task(i, args) >> checkpoint_task
        trigger(f'{prefix}_Event', checkpoint_task)

    return dap_Event

