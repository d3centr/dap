import boto3
import os
import subprocess
from pprint import pprint
from datetime import datetime, timezone
from airflow.decorators import task
from airflow.operators.python import get_current_context, PythonOperator
from airflow.operators.trigger_dagrun import TriggerDagRunOperator
from dap.constants import EPOCH_LENGTH

class EthClientNotFoundError(Exception):
    def __init__(self, message):            
        super().__init__(message)

def describe_instance(name):
    ec2 = boto3.client('ec2')
    try:
        return ec2.describe_instances(Filters=[
            {'Name': 'tag:Name', 'Values': [name]},
            {'Name': 'subnet-id', 'Values': [os.environ['SUBNET_A']]},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ])['Reservations'][0]['Instances'][0]
    except IndexError:
        raise EthClientNotFoundError(
            f"no running instance named '{name}' in {os.environ['SUBNET_A']}"
        )

# return IP from instance name in subnet, used to:
# 1) retrieve ip and cores of client from a single name parameter 
#    - avoid extra parameterization and misconfiguration risk for thread management -
# 2) connect Web3 clients without a DNS record or fixed network interface
def eth_ip(eth_client):
    ip = describe_instance(eth_client)['PrivateIpAddress']
    return ip

def allocatable_threads(client):
    cpu = describe_instance(client)['CpuOptions']
    return cpu['CoreCount'] * cpu['ThreadsPerCore'] - 1

@task()
def scale_pool(eth_client, pool_name=''):
    if not pool_name:
        pool_name=eth_client
    # multiply by 10 to allocate fractions of pool slots
    threads = str(allocatable_threads(eth_client) * 10) 
    print(f'DaP ~ scaling {threads} slots in {pool_name} pool')
    context = get_current_context()
    description = 'last updated by %s dag run %s' % (
        context['dag'].dag_id, context['run_id'])
    print(subprocess.check_output(
        ['airflow', 'pools', 'set', pool_name, threads, description]))

def trigger(dag_id, args, always=False, params={}, trigger_kwargs={
    'wait_for_completion': False
}):

    def callable(**kwargs):
        first_block_in_epoch = kwargs['epoch'] * EPOCH_LENGTH
        past = kwargs['last_block'] - first_block_in_epoch >= EPOCH_LENGTH
        print(f"trigger conditions: always is {always} and past epoch is {past}")

        # unless always, do not trigger if current epoch has just been processed
        if past or always:
            KEYS = ['epoch', 'last_block']
            print(f'passing down {KEYS} and params from dag config:')
            pprint(kwargs)
            if 'trigger_run_id' not in trigger_kwargs.keys():
                dt = datetime.now(timezone.utc).isoformat()
                trigger_kwargs.update({
                    'trigger_run_id': f"trigger__{kwargs['epoch']}_{dt}"
                })
            conf = {key: kwargs[key] for key in KEYS}
            # pass the caller's params if no explicit params
            _params = params if params else kwargs['params']
            # discard outdated epoch in params: not to override argument
            if 'epoch' in _params.keys():
                _params.pop('epoch')
            conf.update(_params)
            TriggerDagRunOperator(
                task_id='trigger_op',
                trigger_dag_id=dag_id,
                conf=conf,
                reset_dag_run=True,
                **trigger_kwargs
            ).execute(get_current_context())
        else:
            print("dag trigger has been skipped due to built-in conditions")

    wait = trigger_kwargs['wait_for_completion']
    task_id = dag_id if wait else f'{dag_id}_trigger'
    return PythonOperator(
        task_id=task_id,
        python_callable=callable,
        op_kwargs=args
    )

