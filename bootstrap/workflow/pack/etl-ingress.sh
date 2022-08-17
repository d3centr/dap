#!/bin/bash
lib_path=./workflow/aws/lib
. $lib_path/env.sh --dns
$lib_path/authenticate_with_last_cluster_created.sh

color=`kubectl config current-context | grep -oP '(?<=/)(blue|green)(?=-)'`
DaP_ingress $color/monitor/monitor-grafana/80 grafana
DaP_ingress $color/superset/superset/8088 superset
DaP_ingress $color/spark/sparkubi-thrift/4040 sts
DaP_ingress $color/airflow/airflow-webserver/8080 airflow

