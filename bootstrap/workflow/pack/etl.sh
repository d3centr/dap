#!/bin/bash
. runtime.sh

# bootstrap first for dependencies (Spark SQL, RBAC)
cd ../spark
dap ./pre-install.sh
dap ./install.sh -a sparkubi -p base

cd ../monitor
dap ./pre-install.sh
dap ./install.sh

cd ../superset
dap ./pre-install.sh
dap ./install.sh -p base

cd ../airflow
# ensures that namespace exists to propagate dapp keys
dap ./pre-install.sh
cd ../dapp
# pipelines are integrated with Airflow build and might require private keys
dap ./install.sh -p keys -a airflow
cd ../airflow
dap ./install.sh -p base

. ../DaP/load_ENV.sh
: ${DaP_INGRESS:=`env_path $DaP_ENV/cluster/INGRESS`}
if $DaP_INGRESS; then
    cd ../bootstrap
    dap ./workflow/pack/etl-ingress.sh
fi

