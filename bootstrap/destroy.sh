#!/bin/bash

source ./runtime.sh

echo "DaP ~ going to destroy cluster and AWS objects"
run_workflow dap-cleanup aws/cleanup.sh

echo "DaP ~ cleanup exit code: $?"

