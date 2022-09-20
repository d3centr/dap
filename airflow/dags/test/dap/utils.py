from dap.utils import (
    describe_instance, eth_ip, 
    allocatable_threads, scale_pool,
    trigger
)
from dap.job import put_meta, get_meta
from dap.constants import EPOCH_LENGTH
from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
import os
import subprocess
import json
import boto3
import s3fs
from copy import deepcopy
from datetime import datetime, timedelta

PARAMS = {
    'eth_client': os.environ['ETHEREUM_CLIENT']
}

# verify private ip against the same instance as the default geth interface
@task()
def eth_ip_test():
    client = get_current_context()['dag_run'].conf['eth_client']
    instance = describe_instance(client)
    actual= eth_ip(client)
    expected = [ni['PrivateIpAddress'] for ni in instance['NetworkInterfaces']]
    fixed_ip = os.environ['ETHEREUM_IP']
    print(f"ACTUAL: {actual}")
    print(f"EXPECTED one of: {expected}")
    print(f"FIXED IP (persistent network interface): {fixed_ip}")
    # default instance name should point to network export 'dap-network-geth-ip'
    assert(actual in expected and fixed_ip in expected)

@task()
def pool_check(client, pool):
    actual = json.loads(subprocess.check_output(
        ['airflow', 'pools', 'get', pool, '-o', 'json']
    ))[0]['slots']
    expected = str(allocatable_threads(client) * 10)
    print(f"ACTUAL slots: {actual}")
    print(f"EXPECTED slots: {expected}")
    assert(actual == expected)

TRIGGER_TEST_KEY = 'test/run/default'
@task()
def trigger_test(explicit_params=False):
    bucket = os.environ['TEST_BUCKET']

    if s3fs.S3FileSystem().exists(f'{bucket}/{TRIGGER_TEST_KEY}'):
        boto3.resource('s3').Object(bucket, TRIGGER_TEST_KEY).delete()

    expected = {
        # hardcoded and shared keys from parent to child dag in callable:
        # passed as arguments from previous operator and expanded by PythonOp
        'last_block': EPOCH_LENGTH,
        'epoch': 0
    }
    # params should be passed to triggered dag
    nested_params = {
        # - keys bucket and key match what is expected by 'run_Test'
        # - epoch checks outdated params do not override previous op args
        'bucket': bucket,
        'key': TRIGGER_TEST_KEY,
        'epoch': -1
    }
    expected.update({'params': nested_params})

    context = get_current_context()
    id = f"{context['dag_run'].run_id}_{context['task_instance'].try_number}"
    trigger_kwargs = {
        'wait_for_completion': True,
        'trigger_run_id': f'{id}_{explicit_params}'  # unique id for multiple runs
    }
    # copy expected so object isn't affected by tested function
    expected_copy = deepcopy(expected)
    if explicit_params:
        # empty nested params to make sure that precedence is given to named arg:
        # important override when the triggered dag is different than caller dag
        expected_copy.update({'params': {}})
        trigger('test_Trigger', expected_copy, params=nested_params.copy(), 
            trigger_kwargs=trigger_kwargs).execute(expected_copy)
    else:
        trigger('test_Trigger', expected_copy, 
            trigger_kwargs=trigger_kwargs).execute(expected_copy)
    
    # flatten config like dag trigger
    params = expected.pop('params')
    params.pop('epoch')  # epoch should be taken from output of previous op
    expected.update(params)
    print(f'EXPECTED: {expected}')

    actual = json.loads(
        boto3.resource('s3').Object(
            bucket, 
            TRIGGER_TEST_KEY
        ).get()['Body'].read()
    )
    print(f'ACTUAL: {actual}')
    assert(actual == expected)

@dag(
    schedule_interval=None, 
    start_date=days_ago(2), 
    tags=['test', 'dap'],
    params={
        'bucket': os.environ['TEST_BUCKET'],
        'key': TRIGGER_TEST_KEY
    }
)
def test_Trigger():
    @task()
    def put_conf():
        conf = get_current_context()['dag_run'].conf
        print(f"CONF: {conf}")
        boto3.resource('s3').Object(
            conf['bucket'], conf['key']
        ).put(Body=json.dumps(conf))
    put_conf()
triggered_dag = test_Trigger()

@task()
def job_metadata_test():
    bucket = os.environ['TEST_BUCKET']
    path = 'test/job/meta'
    name = 'sources'
    expected = [{'source': 'a'}, {'source': 'b'}] 
    dt = put_meta(bucket, path, name, expected)
    actual = get_meta(bucket, path, name, dt)
    assert(actual == expected)
    new_dt = (datetime.fromisoformat(dt) + timedelta(days=1)).isoformat()
    try:
        get_meta(bucket, path, name, new_dt)
    except AssertionError:
        return
    raise AssertionError('Outdated metadata should catch an AssertionError.')

@dag(
    schedule_interval=None,
    start_date=days_ago(2),
    params=PARAMS,
    tags=['test', 'dap']
)
def dap_Utils_ok():
    eth_ip_test()
    scale_pool('{{ params.eth_client }}', pool_name='scale-test'
        ) >> pool_check('{{ params.eth_client }}', 'scale-test')
    job_metadata_test()
    # test implicit and explicit params: does not support parallel execution
    trigger_test() >> trigger_test(explicit_params=True)

test_dag = dap_Utils_ok()

