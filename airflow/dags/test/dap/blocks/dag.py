from dap.blocks.dag import batch

from airflow.decorators import dag, task
from airflow.operators.python import get_current_context
from airflow.utils.dates import days_ago
import os
import json
import pyarrow.parquet as pq
import s3fs
import numpy as np
import pandas as pd
from pandas.api.types import CategoricalDtype

PARAMS = {
    'eth_client': os.environ['ETHEREUM_CLIENT'],
    'bucket': os.environ['TEST_BUCKET'],
    'path': 'test/dap/blocks'
}
EPOCH = 444
DATE = '2021-09-29'

@task()
def check_output():
    conf = get_current_context()['dag_run'].conf
    to_drop = ['transactions', 'logsBloom']

    actual = pq.ParquetDataset(
        f"{conf['bucket']}/{conf['path']}",
        filters=[('epoch', '=', EPOCH)],
        filesystem=s3fs.S3FileSystem()
    ).read().to_pandas().drop(columns=to_drop)
    # normalize CategoricalDtype of returned partitions to match exactly
    actual['epoch'] = actual.epoch.astype(np.int64)
    actual['date'] = actual.date.astype(object)

    expected = pd.DataFrame([
        {
            'baseFeePerGas': 43465682043, 
            'difficulty': 8961991429785813, 
            'extraData': b'\xd8\x83\x01\n\x08\x84geth\x88go1.16.8\x85linux', 
            'gasLimit': 30000000, 
            'gasUsed': 29983567, 
            'hash': b"\xe4\xa4\xa6W$\x03(u\x1b'\xc1\xf4b\x8d\xc6\x0c\xd3\x03\xd1;\xda6\x9c\x92;\t\x83\xa4\x91\xb6Y\xcf", 
            'miner': '0x5A0b54D5dc17e0AadC383d2db43B0a0D3E029c4c', 
            'mixHash': b'\x17\x1b,\xa2\xa2\xbc\xa4\xc5P!\x979\x8c\xfa@\x89/\xbe\x85\x92\xa4\xbb\x8e$\xea\xf4\x16\xa0\x88\xba"\x0e', 
            'nonce': b'\xd4<\xc6\xfd\xee\xd2\xb9a', 
            'number': 13320000, 
            'parentHash': b'=\xc6M\xaa\xa1\xdd0\xab\xbe?\x8d(\xa6\xcb\xa1\xfco\r_\xfe}\xe1`\x8f\x88\xb6\x8f\xc9z\x991\x94', 
            'receiptsRoot': b'F\x8aP\x0eX\xed<\x14\xed\xd5\xc8\xd2\xb2\xd3Y\xdc\xdd~\xcc\xfe\x9d\xe4\xc2\xefS4\xde\xc4\xdb\n\x04\x05', 
            'sha3Uncles': b'\x1d\xccM\xe8\xde\xc7]z\xab\x85\xb5g\xb6\xcc\xd4\x1a\xd3\x12E\x1b\x94\x8at\x13\xf0\xa1B\xfd@\xd4\x93G', 
            'size': 122543, 
            'stateRoot': b'\xfd\\\xe7,F \xe7\xc9\xeaI\xe2}\x18\xd8\xa5\xe8\x8e\x89\x0e\x80?@\xfd\x04\xc8/\x9b\xd2.\\\xb7!', 
            'timestamp': 1632909699, 
            'totalDifficulty': '31489221759998905379852', 
            'transactionsRoot': b'\x11\xb9\xcd\xbe\x9c\xe0\x9dP\x1cD\x98\xf2\xb78\xcf\n\xf1\x8e7T\x84f\xb0F\xf6\xd5n\xce^\xb1 \xcd', 
            'uncles': np.array([], dtype=object),
            'epoch': EPOCH,
            'date': DATE
        }, 
        {
            'baseFeePerGas': 48892940035, 
            'difficulty': 8935752775388047, 
            'extraData': b'X3', 
            'gasLimit': 30029295, 
            'gasUsed': 0, 
            'hash': b"\xb8\x82\xedL9$\x80p{\xff\x11\xfb\x9b\xb5R'8\x88\x17\xcf L,]\x929<>=\x07\xd7J", 
            'miner': '0x005e288D713a5fB3d7c9cf1B43810A98688C7223', 
            'mixHash': b'\x05C\xa4.\\\xa2\xe4d+\xfb\xd8I.\x19S\x1az\xaebV\x83\x07\xda\xf6\x87|y\xddv\x93o\xc3', 
            'nonce': b"\xceV{\xb8\xa4V'\x9a", 
            'number': 13320001, 
            'parentHash': b"\xe4\xa4\xa6W$\x03(u\x1b'\xc1\xf4b\x8d\xc6\x0c\xd3\x03\xd1;\xda6\x9c\x92;\t\x83\xa4\x91\xb6Y\xcf", 
            'receiptsRoot': b'V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!', 
            'sha3Uncles': b'\x1d\xccM\xe8\xde\xc7]z\xab\x85\xb5g\xb6\xcc\xd4\x1a\xd3\x12E\x1b\x94\x8at\x13\xf0\xa1B\xfd@\xd4\x93G', 
            'size': 527, 
            'stateRoot': b'^B)l\xed\x9e\xc1\xa8\x1a\xa6\xee\xb4h\x90\x0eVP\xc4\x80\x81\x90\xb4\xbf\xdd\xd1D\xa8\xe1\x02\xcf\xb5\xfd', 
            'timestamp': 1632909763, 
            'totalDifficulty': '31489230695751680767899', 
            'transactionsRoot': b'V\xe8\x1f\x17\x1b\xccU\xa6\xff\x83E\xe6\x92\xc0\xf8n[H\xe0\x1b\x99l\xad\xc0\x01b/\xb5\xe3c\xb4!', 
            'uncles': np.array([], dtype=object),
            'epoch': EPOCH,
            'date': DATE
        }
    ])

    pd.testing.assert_frame_equal(actual, expected)

@dag(
    schedule_interval=None,
    start_date=days_ago(2),
    params=PARAMS,
    tags=['test', 'dap']
)
def dap_Block_ok():
    batch(0, {'epoch': EPOCH}, batch_length=2) >> check_output()

test_dag = dap_Block_ok()

