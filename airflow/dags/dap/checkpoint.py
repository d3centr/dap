import boto3
import s3fs
import json
from airflow.decorators import task
from airflow.operators.python import get_current_context
from web3 import Web3
from dap.utils import eth_ip
from dap.events.etl import data_sources
from dap.constants import EPOCH_LENGTH, MUTABLE_EPOCHS
import logging

KEY_PREFIX = '_HEAD'

logger = logging.getLogger('airflow.task')

def checkpoint_override(epoch, key, head, bucket):
    s3, s3_fs = boto3.resource('s3'), s3fs.S3FileSystem()

    def load(key):
        if s3_fs.exists(f'{bucket}/{key}'):
            object = s3.Object(bucket, key)
            metadata = int(object.get()['Body'].read())
            return metadata
        else:
            return 0

    def is_client_syncing():
        assert(_last_block <= head), ('Blockchain head is lower than this epoch checkpoint. '
            'Is your client syncing?')

    key_prefix = key.split('__')[0]
    if s3_fs.exists(f'{bucket}/{key_prefix}__immutable'):
        immutable_checkpoint = s3.Object(bucket, f'{key_prefix}__immutable')
        immutable_epoch = int(immutable_checkpoint.get()['Body'].read())
        logger.info(
            f'last metadata checkpoint recorded that epoch {immutable_epoch} is immutable')
        mutable_epoch = immutable_epoch + 1
        if mutable_epoch > epoch:
            logger.info(
                f'overriding epoch {epoch} with next mutable period {mutable_epoch}')
            epoch = mutable_epoch
            key = f'{key_prefix}__{epoch}'

    _last_block = load(key)
    if _last_block > 0:
        logger.info(
            f"last load of epoch {epoch} started at block {_last_block} on the chain head")
    is_client_syncing()
    while _last_block >= EPOCH_LENGTH * (epoch + MUTABLE_EPOCHS):
        logger.info(
            f'epoch {epoch} persisted at least {MUTABLE_EPOCHS} epochs ahead: skip')
        epoch += 1
        key = f'{key_prefix}__{epoch}'
        _last_block = load(key)
        is_client_syncing()

    return epoch

def nested_init(bucket, key_prefix=KEY_PREFIX, chain_head_paths=[]):
    # edge case when render_template_as_native_obj must be disabled
    if isinstance(chain_head_paths, str):
        chain_head_paths = json.loads(chain_head_paths.replace("'", '"'))

    def start_epoch(sources):
        min_block = min([source['startBlock'] for source in sources])
        return min_block // EPOCH_LENGTH

    conf = get_current_context()['dag_run'].conf
    logger.info(f'context conf: {conf}')
    dapp = conf.get('dapp', '')
    sources = data_sources(dapp) if dapp else []
    logger.info(f'{len(sources)}{" "+dapp if dapp else ""} source(s) loaded')
    epoch = conf.get('epoch', start_epoch(sources) if sources else 0)

    w3 = Web3(Web3.HTTPProvider(
        f"http://{eth_ip(conf['eth_client'])}:8545"))
    last_block = w3.eth.block_number

    key = f"{conf['path']}/{key_prefix}__{epoch}"
    overridden_epoch = checkpoint_override(epoch, key, last_block, bucket)

    if chain_head_paths:
        s3 = boto3.resource('s3')
        # replace last block with min chain head when dependencies were persisted
        try:
            last_block = min([int(
                s3.Object(bucket, f'{path}__{overridden_epoch}').get()['Body'].read()
            ) for path in chain_head_paths])
        except s3.meta.client.exceptions.NoSuchKey:
            logger.warning(f'at least one of "{chain_head_paths}" does not exist')
            logger.info('dag cannot proceed before dependencies')
            return {'epoch': None}

    return {
        'epoch': overridden_epoch,
        'sources': sources,
        'last_block': last_block
    }

@task()
def initialize_epoch(bucket, key_prefix=KEY_PREFIX, chain_head_paths=[]):
    return nested_init(
        bucket, key_prefix=key_prefix, chain_head_paths=chain_head_paths)

@task()
def checkpoint_epoch(args, key_prefix=KEY_PREFIX):
    context = get_current_context()
    dag_run = context['dag_run']
    conf = dag_run.conf
    path, bucket = conf['path'], conf['bucket']
    last_block, epoch = args['last_block'], args['epoch']
    s3 = boto3.resource('s3')

    key = f"{path}/{key_prefix}__{epoch}"
    metadata = s3.Object(bucket, key)
    metadata.put(Body=str(last_block))

    if last_block >= EPOCH_LENGTH * (epoch + MUTABLE_EPOCHS):
        logger.info(
            f'epoch {epoch} is immutable at block {last_block}: checkpointing')
        immutable_checkpoint = s3.Object(bucket, f'{path}/{key_prefix}__immutable')
        if s3fs.S3FileSystem().exists(f'{bucket}/{path}/{key_prefix}__immutable'):
            if int(immutable_checkpoint.get()['Body'].read()) < epoch:
                immutable_checkpoint.put(Body=str(epoch))
        else:
            immutable_checkpoint.put(Body=str(epoch))

    return args

