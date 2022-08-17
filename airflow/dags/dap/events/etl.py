import os
import boto3
import yaml
import json
from web3 import Web3
from web3._utils.events import get_event_data
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import s3fs
import logging
from concurrent.futures._base import TimeoutError
from dap.utils import eth_ip
from dap.constants import EPOCH_LENGTH

BATCH_LENGTH = 1000

logger = logging.getLogger('airflow.task')

def parse(dapp):
    # parse configuration of event sources from subgraph
    with open(f'dags/dapp/{dapp}/subgraph.yaml') as file:
        return yaml.safe_load(file)

def map_abis(data_sources):
    mappings = []
    for data_source in data_sources:
        mapping = data_source['source']
        abis = {abi['name']: abi for abi in data_source['mapping']['abis']}
        abi = abis[mapping['abi']]
        events = [h['event'] for h in data_source['mapping']['eventHandlers']]
        mapping.update({'abi': abi['file'], 'name': abi['name'], 'events': events})
        mappings.append(mapping)
    return mappings

def data_sources(dapp):
    factories = __import__(f'dapp.{dapp}.factories', fromlist=['FACTORIES'])    
    sources = map_abis(parse(dapp)['dataSources'])
    for source in sources:
        source.update({'is_factory': source['name'] in factories.FACTORIES.keys()})
    return sources

def data_templates(dapp, contracts):
    templates = {t['name']: t for t in map_abis(parse(dapp)['templates'])}
    for contract in contracts: 
        template = templates[contract['name']]
        contract.update({'events': template['events'], 'abi': template['abi']})
    return contracts

def lookahead(epoch, source, event, conf):
    w3 = Web3(Web3.WebsocketProvider(
        f"ws://{eth_ip(conf['eth_client'])}:8546", websocket_timeout=60))
    with open(f"dags/dapp/{conf['dapp']}/{source['abi']}") as file:
        abi = json.load(file)
    contract = w3.eth.contract(address=source['address'], abi=abi)
    events = contract.events[event].createFilter(
        fromBlock = EPOCH_LENGTH * epoch,
        toBlock   = EPOCH_LENGTH * (1 + epoch) - 1
    ).get_all_entries()
    return events

def process_batch(batch):
    batch = [dict(log) for log in batch]
    for log in batch:
        # turn args into json to prevent overflow and normalize schema
        log.update({'args': json.dumps(dict(log['args']))}) 
    return batch

def job(thread, thread_index, epoch, conf, partitioner, early_stop=False):
    dapp = conf['dapp']

    def event_filter(signature):
        return Web3.keccak(text=signature.replace('indexed ', '')).hex()

    def event_topic(abi):
        arguments = ','.join([input['internalType'] for input in abi['inputs']])
        signature = f"{abi['name']}({arguments})"
        return Web3.keccak(text=signature)

    def get_batch(w3, addresses, topics, block_index):
        batch = w3.eth.get_logs({
            'address': addresses, 
            'fromBlock': block_index, 
            'toBlock': block_index + BATCH_LENGTH - 1, 
            'topics': topics
        })
        return batch
    
    def decode(batch, codec, abis):
        return [
            get_event_data(codec, abis[log.topics[0]], log) 
            for log in batch
        ]

    logger.info(f'collecting {dapp.upper()} input events')
    logger.info(f'epoch {epoch}')
    logger.info(f'thread {thread_index}')

    addresses = [source['address'] for source in thread]
    events = {e for source in thread for e in source['events']}
    # items of single nested list select any matching first topic:
    # in a non-anonymous event, topics[0] is the signature of the event
    topics = [[event_filter(e) for e in events]]
    event_abis = {}
    for path in {source['abi'] for source in thread}:
        with open(f'dags/dapp/{dapp}/{path}') as file:
            contract_abi = json.load(file)
        event_abis.update({event_topic(abi): abi 
            for abi in contract_abi if abi['type'] == 'event'})

    logs = []
    if partitioner == 'block':
        epoch_index = thread_index * BATCH_LENGTH
        start = epoch * EPOCH_LENGTH + epoch_index
        end = start + BATCH_LENGTH
        filename = start
    else:
        start = epoch * EPOCH_LENGTH
        end = start + EPOCH_LENGTH
        filename = thread_index
    w3 = Web3(Web3.WebsocketProvider(f"ws://{eth_ip(conf['eth_client'])}:8546", 
        websocket_timeout=60, websocket_kwargs={'max_size': 20000000}))
    for block_index in range(start, end, BATCH_LENGTH):
        logger.info(f'batch {block_index} - {block_index+BATCH_LENGTH-1} blocks')

        try:
            batch = get_batch(w3, addresses, topics, block_index)
        except TimeoutError as e:
            logger.error('non-stopping timeout error: batch to be retried once')
            batch = get_batch(w3, addresses, topics, block_index)

        if batch:
            batch = process_batch(decode(batch, w3.codec, event_abis))
            logs.append(batch)

        if early_stop and logs:
            break

    if logs:
        # lookup data to partition addresses in retrieved logs by contract:
        contracts = {source['address']: source['name'] for source in thread}
        # flatten logs
        logs = [log for batch in logs for log in batch]
        for log in logs:
            # add partition fields to logs
            log.update({'epoch': epoch, 'contract': contracts[log['address']]})
        table = pa.Table.from_pandas(pd.DataFrame(logs))

        pq.write_to_dataset(
            table,
            f"{conf['bucket']}/{conf['path']}",
            filesystem=s3fs.S3FileSystem(),
            # keep partition order for query efficiency: 
            # could break hardcoded paths targeting a contract if changed
            partition_cols=['contract', 'epoch'],
            compression='SNAPPY',
            partition_filename_cb=lambda _: f'{filename}.parquet.snappy'
        )
    else:
        logger.info('no log found')

