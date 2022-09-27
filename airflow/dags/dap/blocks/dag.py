from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
from airflow.models.param import Param
import os
import s3fs
import boto3
from web3 import Web3
from web3.datastructures import AttributeDict
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import datetime
from dap.constants import EPOCH_LENGTH
from dap.utils import scale_pool, eth_ip, trigger
from dap.checkpoint import initialize_epoch, checkpoint_epoch

PARAMS = {
    'eth_client': os.environ['ETHEREUM_CLIENT'],
    'epoch': 411,  # start an epoch before Uniswap v3 launch
    'bucket': os.environ['DATA_BUCKET'],
    'path': 'blocks'
}
BATCH_LENGTH = 1000
assert(EPOCH_LENGTH % BATCH_LENGTH == 0)
threads = EPOCH_LENGTH // BATCH_LENGTH

# on regular instances, 4 GiB available per vCPU: 
# memory has ample margin to break above request (cpu bottleneck)
@task(executor_config={
    'KubernetesExecutor': {
        'request_cpu': '800m',
        'request_memory': '800Mi'
    }},
    pool=PARAMS['eth_client'],
    pool_slots=2
)
def batch(index, args, batch_length=BATCH_LENGTH):
    conf = get_current_context()['params']
    w3 = Web3(Web3.WebsocketProvider(
        f"ws://{eth_ip(conf['eth_client'])}:8546", 
        websocket_timeout=60, websocket_kwargs={'max_size': 10000000}))

    blocks, last_block = [], args['last_block']
    start = args['epoch'] * EPOCH_LENGTH + index
    for block in range(start, start + batch_length):
        if block <= last_block:
            blocks.append(w3.eth.get_block(block, full_transactions=True))

    blocks = [dict(block) for block in blocks]
    for block in blocks:
        block.update({
            'transactions': [dict(t) for t in block['transactions']],
            # prevent OverflowError in pyarrow handling
            'totalDifficulty': str(block['totalDifficulty'])})
        for transaction in block['transactions']:
            transaction.update({'value': str(transaction['value'])})
            transaction.update({
                k: [dict(x) for x in v] for k, v in transaction.items()
                if (isinstance(v, list) and len(v) > 0 
                    and isinstance(v[0], AttributeDict))})

    if blocks:
        df = pd.DataFrame(blocks)
        df['epoch'] = args['epoch']
        df['date'] = df.timestamp.apply(
            lambda t: datetime.utcfromtimestamp(t).strftime('%Y-%m-%d'))

        pq.write_to_dataset(
            pa.Table.from_pandas(df),
            f"{conf['bucket']}/{conf['path']}",
            filesystem=s3fs.S3FileSystem(),
            # epoch partition must come first to handle schema evolution in Spark
            partition_cols=['epoch', 'date'],
            compression='SNAPPY',
            partition_filename_cb=lambda _: f'{start}.parquet.snappy'
        )

    return args

@dag(
    default_args={
        'retries': 1
    },
    schedule_interval='10 0 * * *',
    max_active_runs=1,
    start_date=days_ago(1),
    catchup=False,
    params=PARAMS,
    tags=['job', 'dap']
)
def dap_Block():
    args = initialize_epoch('{{ params.bucket }}')
    scale_pool('{{ params.eth_client }}') >> args
    checkpoint_task = checkpoint_epoch(args)
    for i in range(threads):
        batch(i * BATCH_LENGTH, args) >> checkpoint_task
    trigger('dap_Block', checkpoint_task)

block_dag = dap_Block()

