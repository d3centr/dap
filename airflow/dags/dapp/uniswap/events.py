# extract Uniswap events in just above a minute per day on 30 threads (1k blocks per thread)
from dap.events.dag import dapp

# give Geth 8 CPUs before triggering this dag: `./stack.sh geth.yaml InstanceSize=2xlarge`
airflow_dag = dapp('uniswap', 'uni')()

