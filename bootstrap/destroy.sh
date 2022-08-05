#!/bin/bash

source ./runtime.sh

echo "DaP ~ going to destroy cluster and/or AWS objects"
run_workflow workflow/aws/cleanup.sh $@

echo "DaP ~ cleanup exit code: $?"

