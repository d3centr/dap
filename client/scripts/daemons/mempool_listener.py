#!/opt/pyd/bin/python

import os
import time
from systemd import journal

s3_prefix = f"s3://{os.environ['SINK_BUCKET']}/data/{os.environ['AWS_REGION']}/"

while True:
  journal.write(time.time())
  time.sleep(1)

