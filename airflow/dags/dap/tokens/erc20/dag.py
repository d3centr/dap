from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
import os
import s3fs
import json
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import mmh3
from web3 import Web3
from dap.utils import eth_ip, scale_pool

PARAMS = {
    'source': f"{os.environ['DATA_BUCKET']}/uniswap/shards=0/contract=Factory", 
    'fields': ['args.token0', 'args.token1'], 
    'abis': {
        'ERC20': 'dags/dapp/uniswap/abis/ERC20.json',
        'ERC20SymbolBytes': 'dags/dapp/uniswap/abis/ERC20SymbolBytes.json'
    },
    'eth_client': os.environ['ETHEREUM_CLIENT'],
    'sink': f"{os.environ['DATA_BUCKET']}/tokens/erc20",
    'epoch': 412
}
THREADS = 1

@task()
def initialize(epoch=-1):
    conf = get_current_context()['dag_run'].conf
    epoch = conf['epoch'] if epoch == -1 else epoch
    s3_fs = s3fs.S3FileSystem()

    fields = [f.split('.') for f in conf['fields']]
    columns = {f[0] for f in fields}
    df = pq.ParquetDataset(
        conf['source'], 
        filters=[('epoch', '=', epoch)],
        filesystem=s3_fs
    ).read(columns).to_pandas()

    tokens = set()  # unique ERC20 token addresses
    for col in columns:
        if col == 'args':
            keys = [f[1] for f in fields if f[0] == 'args']
            args = pd.json_normalize(df.args.apply(json.loads))[keys]
            tokens.update(np.unique(args))
        else:
            tokens.update(np.unique(df[col]))

    try:
        # earlier data only not to miss tokens in current epoch:
        # i.e. in case of partial write failure or incomplete epoch,
        # data will be overwritten
        existing_records = pq.ParquetDataset(
            conf['sink'],
            filesystem=s3_fs,
            filters=[('epoch', '<', epoch)],
            # throw file not found instead of generic OSError
            use_legacy_dataset=False
        ).read(['address']).to_pandas()['address'].to_list()
    except FileNotFoundError:
        print('empty output path')
        existing_records = []

    threads = [[] for _ in range(THREADS)]
    for token in tokens:
        if token not in existing_records:
            i = mmh3.hash(token, signed=False) % THREADS
            threads[i].append(token)
    return threads

@task(pool=PARAMS['eth_client'], pool_slots=1)
def batch(threads, i):
    thread = threads[i]

    conf = get_current_context()['dag_run'].conf
    with open(conf['abis']['ERC20']) as file:
        abi = json.load(file)
    w3 = Web3(Web3.WebsocketProvider(
        f"ws://{eth_ip(conf['eth_client'])}:8546", websocket_timeout=60))

    tokens = []
    for address in thread:
        print(f'pulling token info from {address} contract')
        contract = w3.eth.contract(address, abi=abi)
        try:
            symbol = contract.functions.symbol().call()
        except ConnectionRefusedError as e:
            raise Exception('symbol call on ERC20 contract failed') from e
        except OverflowError as e:
            print('OverflowError likely due to byte symbol: changing string abi')
            with open(conf['abis']['ERC20SymbolBytes']) as file:
                byte_symbol = json.load(file)
            byte_contract = w3.eth.contract(address, abi=byte_symbol)
            try:
                encoded = byte_contract.functions.symbol().call()
                # ! stripped empty bytes remove 0s in last symbol characters
                symbol = bytes.fromhex(encoded.hex().rstrip("0")).decode('utf-8')
            except Exception as e:
                print(f'Substituting address for symbol due to: {e}')
                symbol = address
        except Exception as e:
            print(f'Substituting address for symbol due to: {e}')
            symbol = address
        try:
            decimals = contract.functions.decimals().call()
        except Exception as e:
            print(f'Defaulting to 0 decimals due to: {e}')
            decimals = 0
        tokens.append({
            'address': address, 
            'symbol': symbol, 
            'decimals': decimals,
            'epoch': conf['epoch']
        })

    if tokens:  # prevent from erasing existing records with empty dataset
        print(f"persisting {len(tokens)} tokens")
        pq.write_to_dataset(
            pa.Table.from_pandas(pd.DataFrame(tokens)),
            conf['sink'],
            filesystem=s3fs.S3FileSystem(),
            partition_cols=['epoch'],
            compression='SNAPPY',
            partition_filename_cb=lambda _: f'{i}.parquet.snappy'
        )

@dag(
    default_args={
        'retries': 1
    },
    schedule_interval=None,
    start_date=days_ago(2),
    params=PARAMS,
    tags=['job', 'dap']
)
def dap_ERC20():
    threads = initialize()
    scale_pool(PARAMS['eth_client']) >> threads
    for i in range(THREADS):
        batch(threads, i)

erc20_dag = dap_ERC20()

