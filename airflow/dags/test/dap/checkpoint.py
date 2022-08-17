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

    s3.Object(bucket, key).put(Body=str(REPROC_LIMIT - 1))
    print(('The epoch of a checkpoint which is '
        f'less than {MUTABLE_EPOCHS} epoch old should be reprocessed.'))
    actual = checkpoint_override(0, key, REPROC_LIMIT, bucket)
    print(f"ACTUAL: {actual}")
    print(f"EXPECTED: 0")
    assert(actual == 0)

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
def mutable_epoch_override_test():
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
    conf = get_current_context()['dag_run'].conf
    conf.update({'epoch': 9})
    args = nested_init(bucket, key_prefix='NO_KEY')  # bypass override
    conf.pop('epoch')  # clean shared context
    return args
@task()
def epoch_init_check(args):
    assert_init(args)
    assert(args['epoch'] == 9)
    assert(args['sources'] == [])

@task()
def dapp_init(bucket):
    conf = get_current_context()['dag_run'].conf
    conf.update({'dapp': 'uniswap'})
    args = nested_init(bucket, key_prefix='NO_KEY')
    conf.pop('dapp')
    return args
@task()
def dapp_init_check(args):
    assert_init(args)
    # expecting first epoch from start_block entries in subgraph.yaml
    assert(args['epoch'] == 412)
    assert(args['sources'] == DATA_SOURCES)

@task()
def mixed_init(bucket):
    conf = get_current_context()['dag_run'].conf
    conf.update({'dapp': 'uniswap', 'epoch': 9})
    args = nested_init(bucket, key_prefix='NO_KEY')
    [conf.pop(key) for key in ['dapp', 'epoch']]
    return args
@task()
def mixed_init_check(args):
    assert_init(args)
    # explicit epoch configuration has precedence over first epoch
    assert(args['epoch'] == 9)
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

@dag(
    schedule_interval=None,
    start_date=days_ago(2),
    params=PARAMS,
    tags=['test', 'dap'],
    render_template_as_native_obj=True
)
def dap_Checkpoint_ok():
    checkpoint_override_test()
    out_of_sync_test()
    mutable_epoch_override_test()

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

    chain_head = initialize_epoch('{{ params.bucket }}', 
        chain_head_paths=[PARAMS['path']+b for b in ['/last_block', '/new_block']])
    chain_head_checkpoints(
        '{{ params.bucket }}', '{{ params.path }}'
    ) >> chain_head >>  head_path_check(chain_head)

test_dag = dap_Checkpoint_ok()

