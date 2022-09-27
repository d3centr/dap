#!/bin/bash
set -eo pipefail

## Runtime Configuration
help () { echo "
    usage: ./submit.sh [-c config] <app name> <spark job type> <script>
    [ ... ]: optional
    - config: non-default config name in spark/<app name>/config
    - spark job type: epoch (^[0-9]+$) or date (^[0-9]{4}(-[0-9]{2}){2}$) argument for submit; 
        'shell', 'script' or 'thrift' otherwise
    - script: name of spark-shell script, valid only when job type is 'script'
";}

config=default
args=()  # positional arguments
while (( $# )); do
    case $1 in
        -c|--config) shift; config=$1;;
        -h|--help) help; exit;;
        -*) echo "unknown $1 option" >&2; help; exit 1;;
        *) args+=( $1 );;
    esac
    shift
done
# make positional args the whole argument list to skip processed named args
set -- ${args[@]}

app=${1///}
# default SparkUBI settings
SPARKUBI_PRECISION=200
SPARKUBI_SIMPLIFY=100
SPARKUBI_MIN_BITS=192
SPARKUBI_RESCALE=true
SPARKUBI_PROFILING=false
if [ -d $app ]; then
    . $app/config/$config  # can override SparkUBI variables
    . $app/config/VERSIONS
else
    eval "`kubectl get cm -n spark $app-config \
        -o \"jsonpath={.data['VERSIONS', '\"$config\"']}\"`"
fi

shell_jars="/opt/spark/work-dir/dap/spark/$app/target/scala-$SCALA_VERSION/\*.jar"
if [ $2 = shell ]; then
    client=shell
    name=$app
    command=shell
    tag=$app-builder-$APP_VERSION
    load="--jars $shell_jars"
elif [ $2 = script ]; then
    client=script
    name=$app-${3/_/-}
    command=shell
    tag=$app-builder-$APP_VERSION
    load="-i /opt/spark/work-dir/dap/spark/$app/scripts/$3.scala --jars $shell_jars"
elif [ $2 = thrift ]; then
    client=thrift
    name=$app
    command=submit
    tag=$app-$APP_VERSION
    load="--class org.apache.spark.sql.hive.thriftserver.HiveThriftServer2"
else
    client=submit
    command=submit
    tag=$app-$APP_VERSION
    load="--class $class"
    if [[ $2 =~ ^[0-9]+$ ]]; then 
        epoch=$2
        name=$app-$epoch
    elif [[ $2 =~ ^[0-9]{4}(-[0-9]{2}){2}$ ]]; then 
        _date=$2
        name=$app-d${_date//-}
    fi
fi

garbage_collection () {
    uid=`kubectl get job -n spark $name-$client -o jsonpath='{.metadata.uid}'`
    ref='{"apiVersion":"batch/v1","kind":"Job","name":"'$name-$client'","uid":"'$uid'"}'
    # set owner reference on dependent objects
    patch='{"metadata":{"ownerReferences":['$ref']}}'
    kubectl patch svc $name-$client -n spark -p $patch
    kubectl patch cm $name-$client -n spark -p $patch
}
has_succeeded () {
    local status=`kubectl get job -n spark $name-$client \
        -o custom-columns=":status.succeeded" --no-headers`
    [ $status = 1 ]
}
attach_client () {
    if [ -f /.dockerenv ]; then
        kubectl attach -n spark job/$name-$client
    elif [[ $client =~ ^(shell|script)$  ]]; then
        kubectl attach -in spark job/$name-$client
    elif [ $client = submit ]; then
        kubectl logs -n spark job/$name-$client -f
    fi
    has_succeeded || {
        # late status more prone to happen in spark scripts
        sleep 3  # give some time for pod exit to propagate
        has_succeeded || {
            sleep 3
            has_succeeded
        }
    }
}
echo "DaP ~ checking if $name-$client job already exists"
status_check=`kubectl get job -n spark $name-$client \
    -o custom-columns=":status.active" --no-headers --ignore-not-found`
# if job exists and client is healthy (can attach):
# exit script upon completion, delete job and proceed otherwise
if [ "$status_check" = 1 ]; then
    echo "DaP ~ identical job name is already active: patching GC and attaching"
    garbage_collection  # in case container went down before completion
    attach_client
    exit $?
# non-empty string indicates that job exists event though active status is none
elif [ -n "$status_check" ]; then
    echo "DaP ~ identical job name isn't active: deleting"
    kubectl delete job -n spark $name-$client
else  # status check is empty
    echo "DaP ~ job name not found: proceeding"
fi

## Job
if [ -f /.dockerenv ]; then 
    echo "found /.dockerenv: submit will attempt to run on local k8s"
    stdin=false
else
    stdin=true
    echo "/.dockerenv wasn't found: authenticating with k8s outside container"
    # authenticate with cluster and declare REGISTRY
    source `git rev-parse --show-toplevel`/bootstrap/app-init.sh
    # default for local spark submit override of sink bucket: no need to call kubectl
    DELTA_BUCKET=$CLUSTER-$REGION-delta-$ACCOUNT
fi

DRIVER_PORT=35743
STATE_STORE=org.apache.spark.sql.execution.streaming.state.RocksDBStateStoreProvider
CATALOG=org.apache.spark.sql.delta.catalog.DeltaCatalog
DELTA_SQL=io.delta.sql.DeltaSparkSessionExtension
env="
        - name: SPARKUBI_PRECISION
          value: \"$SPARKUBI_PRECISION\"
        - name: SPARKUBI_SIMPLIFY
          value: \"$SPARKUBI_SIMPLIFY\"
        - name: SPARKUBI_MIN_BITS
          value: \"$SPARKUBI_MIN_BITS\"
        - name: SPARKUBI_RESCALE
          value: \"$SPARKUBI_RESCALE\"
        - name: SPARKUBI_PROFILING
          value: \"$SPARKUBI_PROFILING\"
"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $name-$client
  namespace: spark
spec:
  clusterIP: None
  ports:
  - name: driver
    port: $DRIVER_PORT
    protocol: TCP
    targetPort: $DRIVER_PORT
  - name: ui
    port: 4040
    protocol: TCP
    targetPort: 4040
  - name: thrift
    port: 10000
    protocol: TCP
    targetPort: 10000
  selector:
    job-name: $name-$client
  type: ClusterIP
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: $name-$client
  namespace: spark
data:
  submit.sh: |
    #!/bin/bash

    /opt/spark/bin/spark-$command \
        $load \
        --master k8s://https://kubernetes.default.svc.cluster.local:443 \
        --driver-memory $DRI_MEM \
        --num-executors $NUM_EXE \
        --executor-cores $EXE_COR \
        --executor-memory $EXE_MEM \
        --conf spark.driver.host=$name-$client.spark.svc.cluster.local \
        --conf spark.driver.port=35743 \
        --conf spark.kubernetes.namespace=spark \
        --conf spark.kubernetes.driver.pod.name=\$HOSTNAME \
        --conf spark.kubernetes.executor.label.app=$app \
        --conf spark.kubernetes.container.image=$REGISTRY/spark:$tag \
        --conf spark.kubernetes.container.image.pullPolicy=Always \
        --conf spark.hadoop.fs.s3.impl=org.apache.hadoop.fs.s3a.S3AFileSystem \
        --conf spark.sql.extensions=$DELTA_SQL,fyi.dap.sparkubi.Extensions \
        --conf spark.sql.catalog.spark_catalog=$CATALOG \
        --conf spark.sql.streaming.stateStore.providerClass=$STATE_STORE \
        --conf spark.kubernetes.executor.podTemplateFile=/mnt/pod-template.yaml \
        --conf spark.sql.hive.thriftServer.singleSession=true \
        --conf spark.driver.dap.epoch=${epoch:-"-1"} \
        --conf spark.driver.dap.date=${_date:-"0000-00-00"} \
        --conf spark.driver.dap.sinkBucket=${SINK_BUCKET:-$DELTA_BUCKET} \
        /opt/spark/jars/${app}_$SCALA_VERSION-$APP_VERSION.jar

  pod-template.yaml: |
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: env
        env: $env
        resources:
          requests:
            ephemeral-storage: 16Gi
      tolerations:
      - key: spark
        operator: Equal
        value: exec
        effect: NoSchedule
---
apiVersion: batch/v1
kind: Job
metadata:
  name: $name-$client
  namespace: spark
spec:
  # do not set close to 0, status is tracked through job
  ttlSecondsAfterFinished: 1200
  # disable retries so they're managed by caller, e.g. service pod or airflow
  backoffLimit: 0
  template:
    metadata:
      name: $name-$client
    spec:
      restartPolicy: Never
      serviceAccountName: spark
      containers:
      - name: $name-$client
        image: $REGISTRY/spark:$tag
        imagePullPolicy: Always
        args:
        - /mnt/submit.sh
        volumeMounts:
        - name: command
          mountPath: /mnt
        - name: conf
          mountPath: /opt/spark/conf
        stdin: $stdin
        tty: $stdin
        envFrom:
        - configMapRef:
            name: env
        env: $env
        resources:
          requests:
            memory: 1Gi
            cpu: 800m
      volumes:
      - name: command
        configMap:
          name: $name-$client
          defaultMode: 0777
      - name: conf
        configMap:
          name: sparkubi-hive-site
EOF

## Garbage Collection
garbage_collection

## Status
counter=0
client_status () {
    ((counter++))
    local status=`kubectl get pod -n spark -l job-name=$name-$client \
        -o custom-columns=":status.phase" --no-headers`
    echo client pod $status
    [[ $status =~ ^(Running|Succeeded)$ ]]
}
until client_status || [ $counter -ge 300 ]; do sleep 2; done
attach_client

