from dap.tokens.erc20.dag import THREADS, initialize, batch

from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
import os
import json
import pyarrow as pa
import pyarrow.parquet as pq
import boto3
import s3fs
import pandas as pd

bucket = os.environ['TEST_BUCKET']
output_path = 'test/dap/erc20/output'
PARAMS = {
    'source': f'{bucket}/test/dap/erc20/input', 
    'fields': ['args.token0', 'args.token1'], 
    'abis': {
        'ERC20': 'dags/dapp/uniswap/abis/ERC20.json',
        'ERC20SymbolBytes': 'dags/dapp/uniswap/abis/ERC20SymbolBytes.json'
    },
    'eth_client': os.environ['ETHEREUM_CLIENT'],
    'sink': f'{bucket}/{output_path}',
    'epoch': 412
}

@task()
def clear_output():
    s3_fs, s3 = s3fs.S3FileSystem(), boto3.resource('s3')
    conf = get_current_context()['dag_run'].conf
    for thread in range(THREADS):
        file = f"epoch={conf['epoch']}/{thread}.parquet.snappy"
        if s3_fs.exists(f"{conf['sink']}/{file}"):
            s3.Object(bucket, f'{output_path}/{file}').delete()

@task()
def create_input():
    input = [
        json.dumps({
            "token0": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 
            "token1": "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        }),
        json.dumps({
            # MKR symbol encoded in bytes32 (edge case)
            "token0": "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2", 
            "token1": "0x514910771AF9Ca656af840dff83E8264EcF986CA"
        })
    ]
    pq.write_to_dataset(
        pa.Table.from_pandas(pd.DataFrame({'args': input})),
        get_current_context()['dag_run'].conf['source'],
        filesystem=s3fs.S3FileSystem(),
        compression='SNAPPY',
        partition_filename_cb=lambda _: '0.parquet.snappy'
    )

@task()
def check_output():

    actual = pq.ParquetDataset(
        get_current_context()['dag_run'].conf['sink'], 
        filesystem=s3fs.S3FileSystem(),
        use_legacy_dataset=False  # tolerate empty thread output
    ).read().to_pandas().sort_values('symbol').set_index(
        pd.RangeIndex(start=0, stop=4, step=1)
    ).drop('epoch', axis=1)

    expected = pd.DataFrame({
        'address': [
            '0x514910771AF9Ca656af840dff83E8264EcF986CA',
            '0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2',
            '0xdAC17F958D2ee523a2206206994597C13D831ec7',
            '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'
        ],
        'symbol': ['LINK', 'MKR', 'USDT', 'WETH'],
        'decimals': [18, 18, 6, 18]
    })

    pd.testing.assert_frame_equal(actual, expected)

@task()
def no_past_dupe(threads):
    for thread in threads:
        assert(not thread)

@dag(
    schedule_interval=None,
    start_date=days_ago(2),
    params=PARAMS,
    concurrency=1,
    tags=['test', 'dap']
)
def dap_ERC20_ok():
    threads = initialize()
    [create_input(), clear_output()] >> threads
    check = check_output()
    for i in range(THREADS):
        batch(threads, i) >> check
    new_threads = initialize(epoch=413)
    check >> new_threads >> no_past_dupe(new_threads)

test_dag = dap_ERC20_ok()

