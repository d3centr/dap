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
        if head is not None:
            assert(_last_block <= head), (
                f'Chain head ({head}) is lower than epoch {epoch} checkpoint'
                f' ({_last_block}). Is your client syncing?'
            )

    def iterate(epoch):
        epoch += 1
        key = f'{key_prefix}__{epoch}'
        _last_block = load(key)
        is_client_syncing()
        return epoch, _last_block

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
        if head is None:
            logger.info(f'last load of epoch {epoch} occurred at block {_last_block}')
        else:
            logger.info(
                f'last load of epoch {epoch} started {head - _last_block} block(s) ago')
    is_client_syncing()

    while _last_block >= EPOCH_LENGTH * (epoch + MUTABLE_EPOCHS):
        logger.info(
            f'epoch {epoch} persisted at least {MUTABLE_EPOCHS} epochs ahead: skip')
        epoch, _last_block = iterate(epoch)

    # Chain head relevant in extraction dags relying on a blockchain client: 
    # head is None when a dag depends on persisted datasets.
    # -> take a checkpoint substitute to know if the epoch is mutable in dependent dags
    block_height = _last_block if head is None else head
    mutable_period_length = EPOCH_LENGTH * MUTABLE_EPOCHS
    # Conditions to load latest data when current mutable period is complete:
    #     [                   = is epoch mutable?                                 ]
    #     [                   = confirmation blocks      ] 
    #                     [   = last block in epoch      ]
    while (block_height - ((epoch + 1) * EPOCH_LENGTH - 1) < mutable_period_length and 
    # [       = is epoch complete?                              ]
    # [       = blocks from epoch start        ]
    #                 [  = end previous epoch  ]
        _last_block - (epoch * EPOCH_LENGTH - 1) >= EPOCH_LENGTH):
        logger.info(f"epoch {epoch} is in the latest mutable period and complete: next")
        epoch, _last_block = iterate(epoch)

    return epoch

def nested_init(bucket, key_prefix=KEY_PREFIX, head_paths=[]):
    # edge case when render_template_as_native_obj must be disabled
    if isinstance(head_paths, str):
        head_paths = json.loads(head_paths.replace("'", '"'))

    def start_epoch(sources):
        min_block = min([source['startBlock'] for source in sources])
        return min_block // EPOCH_LENGTH

    params = get_current_context()['params']
    logger.info(f'context params: {params}')
    dapp = params.get('dapp', '')
    sources = data_sources(dapp) if dapp else []
    logger.info(f'{len(sources)}{" "+dapp if dapp else ""} source(s) loaded')
    epoch = params.get('epoch', start_epoch(sources) if sources else 0)

    if head_paths:
        last_block = None
    else:
        w3 = Web3(Web3.HTTPProvider(
            f"http://{eth_ip(params['eth_client'])}:8545"))
        last_block = w3.eth.block_number

    key = f"{params['path']}/{key_prefix}__{epoch}"
    overridden_epoch = checkpoint_override(epoch, key, last_block, bucket)

    if head_paths:
        s3 = boto3.resource('s3')

        def path_head(epoch):
            return min([int(
                s3.Object(bucket, f'{path}__{epoch}').get()['Body'].read()
            ) for path in head_paths])

        # replace last block with min chain head when dependencies were persisted
        try:
            last_block = path_head(overridden_epoch)
            logger.info(f'head from paths of epoch override: {last_block}')
        except s3.meta.client.exceptions.NoSuchKey:
            logger.warning(f'at least one of "{head_paths}" does not exist')
            logger.info('dag cannot proceed before dependencies')
            return {'epoch': None}

    return {
        'epoch': overridden_epoch,
        'sources': sources,
        'last_block': last_block
    }

@task()
def initialize_epoch(bucket, key_prefix=KEY_PREFIX, head_paths=[]):
    return nested_init(bucket, key_prefix=key_prefix, head_paths=head_paths)

@task()
def checkpoint_epoch(args, key_prefix=KEY_PREFIX):
    conf = get_current_context()['params']
    path, bucket = conf['path'], conf['bucket']
    last_block, epoch = args['last_block'], args['epoch']
    s3 = boto3.resource('s3')

    key = f"{path}/{key_prefix}__{epoch}"
    metadata = s3.Object(bucket, key)
    logger.info(f'checkpointing chain head metadata for epoch {epoch}')
    metadata.put(Body=str(last_block))

    if last_block >= EPOCH_LENGTH * (epoch + MUTABLE_EPOCHS):
        logger.info(f'checkpointing immutable epoch {epoch} at block {last_block}')
        immutable_checkpoint = s3.Object(bucket, f'{path}/{key_prefix}__immutable')
        if s3fs.S3FileSystem().exists(f'{bucket}/{path}/{key_prefix}__immutable'):
            # allow arbitrary reloads of immutable epochs without affecting checkpoint
            if int(immutable_checkpoint.get()['Body'].read()) < epoch:
                immutable_checkpoint.put(Body=str(epoch))
        else:
            immutable_checkpoint.put(Body=str(epoch))

    return args

