#!/bin/bash

echo "DaP ~ loading environment variables"

export ACCOUNT=`aws sts get-caller-identity --query Account --output text --profile $AWS_PROFILE`
export REGION=`aws configure get region --profile $AWS_PROFILE`

