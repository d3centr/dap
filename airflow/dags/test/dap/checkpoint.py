from dap.checkpoint import (
    nested_init, initialize_epoch,
    checkpoint_override, checkpoint_epoch 
)
from dap.constants import EPOCH_LENGTH, MUTABLE_EPOCHS
from test.dap.events.constants import DATA_SOURCES
from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
import os
import boto3
import s3fs

PARAMS = {
    'eth_client': os.environ['ETHEREUM_CLIENT'],
    'bucket': os.environ['TEST_BUCKET'],
    'path': 'test/dap/checkpoint'
}
# number of confirmation blocks for a workload to be considered immutable
REPROC_LIMIT = EPOCH_LENGTH * MUTABLE_EPOCHS

def s3_params():
    conf = get_current_context()['dag_run'].conf
    return conf['bucket'], conf['path']

# Verify an epoch immutability/mutability based on checkpointed chain head:
# last epoch could still be impacted by chain reorg. and current is incomplete.
# TESTS:
# 1) Historical reload should skip an epoch processed MUTABLE_EPOCHS (2) epochs ahead.
# 2) Historical reload should reprocess mutable epochs (last and current).
@task()
def checkpoint_override_test():
    context = get_current_context()
    conf = context['dag_run'].conf
    bucket = conf['bucket']
    # rewrite prefix delimiter to avoid clash with epoch suffix delimiter
    run_id = context['run_id'].replace('__', '_')
    s3 = boto3.resource('s3')

    # checkpoint_override() relies on '__' epoch suffix delimiter to iterate
    key = f"{conf['path']}/{run_id}__0"
    s3.Object(bucket, key).put(Body=str(REPROC_LIMIT))
    print(('The epoch of a checkpoint which is '
        f'{MUTABLE_EPOCHS} epoch old should NOT be reprocessed.'))
    actual = checkpoint_override(0, key, REPROC_LIMIT, bucket)
    print(f"ACTUAL: {actual}")
    print(f"EXPECTED: 1")
    assert(actual == 1)

    # generic case in past period, current mutable period checked in test below
    s3.Object(bucket, key).put(Body=str(REPROC_LIMIT - 1))
    print(('The epoch of a checkpoint which is '
        f'less than {MUTABLE_EPOCHS} epoch old should be reprocessed.'))
    # adding one more EPOCH_LENGTH to blockchain head to test past reload
    actual = checkpoint_override(0, key, EPOCH_LENGTH + REPROC_LIMIT, bucket)
    print(f"ACTUAL: {actual}")
    print(f"EXPECTED: 0")
    assert(actual == 0)

# edge case / exception should be skipped to load latest data
@task()
def complete_mutable_epoch_test():
    bucket, path = s3_params()
    key = f"{path}/complete_mutable_epoch__0"
    # when extracted, first epoch (0) would be complete if head >= EPOCH_LENGTH
    boto3.resource('s3').Object(bucket, key).put(Body=str(EPOCH_LENGTH))
    actual = checkpoint_override(0, key, EPOCH_LENGTH, bucket)
    assert(actual == 1)  # should override epoch with next

# check edge case condition: by default, a mutable epoch should be reprocessed
@task()
def incomplete_mutable_epoch_test():
    bucket, path = s3_params()
    key = f"{path}/incomplete_mutable_epoch__0"
    # EPOCH_LENGTH - 2 makes epoch 0 incomplete (- 1 does not due to block 0)
    boto3.resource('s3').Object(bucket, key).put(Body=str(EPOCH_LENGTH - 2))
    actual = checkpoint_override(0, key, EPOCH_LENGTH, bucket)
    assert(actual == 0)

@task()
def mutability_limit_test():
    EPOCH = 526
    print(f'EPOCH: {EPOCH}')
    last_block_epoch = (EPOCH + 1) * EPOCH_LENGTH - 1
    reload_threshold = last_block_epoch + REPROC_LIMIT
    bucket, path = s3_params()
    key = f"{path}/mutability_limit__{EPOCH}"
    # simulate an epoch load which started as soon as the last block sync
    boto3.resource('s3').Object(bucket, key).put(Body=str(last_block_epoch))
    # making last block just old enough to trigger an immutable reload
    actual = checkpoint_override(EPOCH, key, reload_threshold, bucket)
    print(f'ACTUAL (reload): {actual}')
    assert(actual == EPOCH)
    # setting confirmation blocks right before immutable reload trigger
    actual = checkpoint_override(EPOCH, key, reload_threshold - 1, bucket)
    print(f'ACTUAL (skip): {actual}')
    assert(actual == EPOCH + 1)

@task()
def checkpoint_check(args):
    bucket, path = s3_params()
    object = boto3.resource('s3').Object(bucket, f"{path}/_HEAD__{args['epoch']}")
    actual = int(object.get()['Body'].read())
    expected = args['last_block']
    assert(actual == expected)

@task()
def out_of_sync_test():
    bucket, path = s3_params()
    boto3.resource('s3').Object(bucket, path+'/out_of_sync').put(Body='2')
    try:
        # blockchain head at block 1 while checkpoint was persisted at block 2
        checkpoint_override(999, path+'/out_of_sync', 1, bucket)
    except AssertionError:
        return
    raise AssertionError(
        'A lower head (1) than an epoch checkpoint (2) should catch an AssertionError.')

@task()
def immutable_epoch_override_test():
    bucket, path = s3_params()
    boto3.resource('s3').Object(bucket, path+'/mutable_override__immutable').put(Body='2')
    actual = checkpoint_override(1, path+'/mutable_override', 0, bucket)
    assert(actual == 3)

@task()
def delete_immutability_meta(key_prefix):
    bucket, path = s3_params()
    key = f'{path}/{key_prefix}__immutable'
    if s3fs.S3FileSystem().exists(f'{bucket}/{key}'):
        boto3.resource('s3').Object(bucket, key).delete()

@task()
def immutable_meta_check(epoch, key_prefix):
    bucket, path = s3_params()
    key = f'{path}/{key_prefix}__immutable'
    print(f'checking {bucket}/{key} object')
    metadata = boto3.resource('s3').Object(bucket, key)
    actual = int(metadata.get()['Body'].read())
    print(f"ACTUAL: {actual}")
    print(f"EXPECTED: {epoch}")
    assert(actual == epoch)

def assert_init(args):
    assert(sorted(args.keys()) == ['epoch', 'last_block', 'sources'])

@task()
def epoch_init(bucket):
    conf = get_current_context()['params']
    conf.update({'epoch': 9})
    args = nested_init(bucket, key_prefix='NO_KEY')  # bypass override
    conf.pop('epoch')  # clean shared context
    return args
@task()
def epoch_init_check(args):
    assert_init(args)
    actual = args['epoch']
    print(f'ACTUAL: {actual}')
    assert(actual == 9)
    assert(args['sources'] == [])

@task()
def dapp_init(bucket):
    conf = get_current_context()['params']
    conf.update({'dapp': 'uniswap'})
    args = nested_init(bucket, key_prefix='NO_KEY')
    conf.pop('dapp')
    return args
@task()
def dapp_init_check(args):
    assert_init(args)
    actual = args['epoch']
    print(f'ACTUAL: {actual}')
    # expecting first epoch from start_block entries in subgraph.yaml
    assert(actual == 412)
    assert(args['sources'] == DATA_SOURCES)

@task()
def mixed_init(bucket):
    conf = get_current_context()['params']
    conf.update({'dapp': 'uniswap', 'epoch': 9})
    args = nested_init(bucket, key_prefix='NO_KEY')
    [conf.pop(key) for key in ['dapp', 'epoch']]
    return args
@task()
def mixed_init_check(args):
    assert_init(args)
    actual = args['epoch']
    print(f'ACTUAL: {actual}')
    # explicit epoch configuration has precedence over first epoch
    assert(actual == 9)
    assert(args['sources'] == DATA_SOURCES)

@task()
def empty_init(bucket):
    keys = get_current_context()['dag_run'].conf.keys()
    # assuming no epoch or dapp key in dag params
    assert('epoch' not in keys and 'dapp' not in keys)
    return nested_init(bucket, key_prefix='NO_KEY')
@task()
def empty_init_check(args):
    assert_init(args)
    assert(args['epoch'] == 0)
    assert(args['sources'] == [])

CHAIN_HEAD = 7777777
@task()
def chain_head_checkpoints(bucket, path):
    s3 = boto3.resource('s3')
    s3.Object(bucket, f'{path}/last_block__0').put(Body=str(CHAIN_HEAD))
    s3.Object(bucket, f'{path}/new_block__0').put(Body=str(CHAIN_HEAD+1))
@task()
def head_path_check(args):
    assert(args['last_block'] == CHAIN_HEAD)
@task()
def none_path_check(args):
    assert(args['epoch'] is None)

@task()
def mutable_head_path_test():
    EPOCH = 526
    bucket, path = s3_params()
    key = f'{path}/mutable_path'
    block = (EPOCH + 1) * EPOCH_LENGTH
    s3 = boto3.resource('s3')
    # checkpoint next epoch first block: epoch is complete but mutable
    s3.Object(bucket, f'{key}__{EPOCH}').put(Body=str(block))
    # adding a block to differentiate logs, next epoch still incomplete
    s3.Object(bucket, f'{key}__{EPOCH + 1}').put(Body=str(block + 1))
    conf = get_current_context()['params']
    conf.update({'epoch': EPOCH})
    # dag and dependency checkpoints in one file only to ease test
    args = nested_init(bucket, key_prefix='mutable_path', head_paths=[key])
    conf.pop('epoch')  # clean context
    actual = args['epoch']
    print(f'ACTUAL: {actual}')
    expected = EPOCH + 1
    print(f'EXPECTED: {expected}')
    assert(actual == expected)

@dag(
    schedule_interval=None,
    start_date=days_ago(2),
    params=PARAMS,
    tags=['test', 'dap'],
    render_template_as_native_obj=True
)
def dap_Checkpoint_ok():
    checkpoint_override_test()
    complete_mutable_epoch_test()
    incomplete_mutable_epoch_test()
    mutability_limit_test()
    out_of_sync_test()
    immutable_epoch_override_test()

    empty_args = empty_init('{{ params.bucket }}')
    epoch_args = epoch_init('{{ params.bucket }}')
    dapp_args = dapp_init('{{ params.bucket }}')
    mixed_args = mixed_init('{{ params.bucket }}')
    # chain initialization scenarios to synchronize shared context
    empty_args >> epoch_args >> dapp_args >> mixed_args
    empty_init_check(empty_args)
    epoch_init_check(epoch_args)
    dapp_init_check(dapp_args)
    mixed_init_check(mixed_args)
    # mutable_head_path_test() also relying on custom context
    mixed_args >> mutable_head_path_test()

    # last_block (chain head) within epoch to test immutability checkpoint below
    mutable_args = {'epoch': 444, 'last_block': 13319999}
    checkpoint_epoch(mutable_args) >> checkpoint_check(mutable_args)

    # test immutability checkpoint creation, update and no update
    confirmed_epoch_1 = EPOCH_LENGTH + REPROC_LIMIT
    key_prefix = '_immutability_checkpoint'
    first_args = {'epoch': 1, 'last_block': confirmed_epoch_1}
    delete_immutability_meta(key_prefix) >> checkpoint_epoch(
        first_args, key_prefix=key_prefix
    ) >> immutable_meta_check(1, key_prefix) >> checkpoint_epoch(
        {'epoch': 2, 'last_block': confirmed_epoch_1 + EPOCH_LENGTH},
        key_prefix=key_prefix
    ) >> immutable_meta_check(2, key_prefix) >> checkpoint_epoch(
        first_args, key_prefix=key_prefix
    ) >> immutable_meta_check(2, key_prefix)

    head_paths = [PARAMS['path']+b for b in ['/last_block', '/new_block']]
    chain_head = initialize_epoch('{{ params.bucket }}', head_paths=head_paths)
    chain_head_2 = initialize_epoch('{{ params.bucket }}', head_paths=head_paths,
        key_prefix='last_block')  # current epoch checkpoint to iterate
    chain_head_checkpoints(
        '{{ params.bucket }}', '{{ params.path }}'
    ) >> chain_head >> head_path_check(chain_head
    ) >> chain_head_2 >> none_path_check(chain_head_2)

test_dag = dap_Checkpoint_ok()

