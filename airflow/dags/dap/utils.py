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

def trigger(dag_id, args, params={}, trigger_kwargs={
    'wait_for_completion': False
}):

    def callable(**kwargs):
        KEYS = ['epoch', 'last_block']
        print(f'passing down {KEYS} and params from dag config:')
        pprint(kwargs)
        context = get_current_context()
        if 'trigger_run_id' not in trigger_kwargs.keys():
            run_id_prefix = context['dag_run'].run_id.split('_')[0]
            dt = datetime.now(timezone.utc).isoformat()
            trigger_kwargs.update({
                'trigger_run_id': f"{run_id_prefix}__{kwargs['epoch']}_{dt}"
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
        ).execute(context)

    wait = trigger_kwargs['wait_for_completion']
    task_id = dag_id if wait else f'{dag_id}_trigger'
    return PythonOperator(
        task_id=task_id,
        python_callable=callable,
        op_kwargs=args
    )

