from airflow.decorators import dag, task
from airflow.utils.dates import days_ago
from airflow.models.param import Param
from airflow.providers.apache.hive.hooks.hive import HiveServer2Hook
import os
import pandas as pd
from dap.constants import EPOCH_LENGTH

PARAMS = {
    'epoch': Param(444, type='integer', minimum=0)
}

@task()
def block_count(epoch):
    count = HiveServer2Hook().get_pandas_df(f"""
        SELECT first(epoch) AS epoch, 
            count(*) as blocks, 
            count(distinct number) as distinct_blocks, 
            min(number) AS first_block, 
            max(number) AS last_block
        FROM parquet.`s3://{os.environ['DATA_BUCKET']}/blocks`
        WHERE epoch = {epoch}
    """)
    print(f"""
{count.to_string()}""")
    assert(count.epoch[0] == epoch)
    assert(count.blocks[0] == EPOCH_LENGTH)
    pd.testing.assert_series_equal(
        count.blocks, count.distinct_blocks, check_names=False)

@dag(
    params=PARAMS,
    schedule_interval=None,
    start_date=days_ago(2),
    tags=['dap', 'check'],
    render_template_as_native_obj=True
)
def dap_Block_io():
    block_count('{{ params.epoch }}')

test_dag = dap_Block_io()

