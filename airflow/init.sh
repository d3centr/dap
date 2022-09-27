#!/bin/bash
source ../bootstrap/app-init.sh

DAPPS=`env_file $DaP_ENV/dapps`
PG_VOLUME=$CLUSTER-airflow-postgresql-0

