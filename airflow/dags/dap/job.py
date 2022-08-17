import boto3
import json
from datetime import datetime, timezone

def key(path, name):
    return f'{path}/_job/{name}.json'

def put_meta(bucket, path, name, content):
    dt = datetime.now(timezone.utc).isoformat()
    boto3.resource('s3').Object(bucket, key(path, name)).put(
        Body=json.dumps(content))
    return dt

def get_meta(bucket, path, name, dt):
    object = boto3.resource('s3').Object(bucket, key(path, name))
    created = datetime.fromisoformat(dt)
    assert(object.last_modified >= created), ('outdated metadata: '
        'check out eventual consistency of object storage')
    return json.loads(object.get()['Body'].read())

