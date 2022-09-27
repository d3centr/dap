# Pipeline

A **dapp** , or DaP pipeline, is a collection of artefacts to be installed on DaP applications from a remote git repo.

A complete data pipeline would typically consist of:

- **Airflow dags** to orchestrate the workflow and run python tasks...
    - by default, dags are integrated in the Airflow environment according to `dapps` config, i.e.\
      *once private keys are configured, no need to go through Install commands below for Airflow*
        - `dap ./install.sh -p keys -a airflow` is already executed at bootstrap to configure keys\
            -> just run the command again if a new deploy key has been added in ~/.dap/pipeline
    - sync Airflow from Argo CD UI to push updates
        - task updates: sync is enough to update the image, tasks should always pull the latest
        - dag updates: restart the scheduler pod to force immediate dag parsing after sync

- **Spark jobs** for the heavy lifting...
    - file tree [example](https://github.com/dapfyi/uniswap-dapp/spark/uniswap), include:
        - `Chart.yaml`: add at least profile and build dependencies as shown
        - `build.sbt`: provides scala build configuration
        - `values.yaml`: `build.baseImage` must be provided

- **Superset dashboards** to visualize...
    - supporting zipped dashboards like Superset API
        - import/export commands available in Superset [doc](/superset)

## Install

1. source the bootstrap runtime `dap` from this folder: `. ../bootstrap/runtime.sh`
2. install configured pipelines per DaP application (Superset, Spark, ...):
```bash
dap ./install.sh -a superset  # to install dashboards
./install.sh --help  # more options
```

## Configuration

See `dapps` key in [DaP](/DaP) and commented version of [default](/DaP/live/dapps/default) config below. Override with a `var` file within the same folder.

```yaml
dapps:

# 'dapp' value refers to:
# 1) the Spark folder to install under <repo>/<path>/spark;
# 2) the Airflow folder to install under <repo>/<path>/airflow/dags/dapp;
# 3) the Airflow test folder to install under <repo>/<path>/airflow/dags/test/dapp;
# 4) the Superset folder to install under <repo>/<path>/superset;
# 5) when repo is private, a deploy key under ~/.dap/pipeline,
# e.g. when repo is a SSH URL, ~/.dap/pipeline/uniswap.pem authenticates the config below.
#
- dapp: uniswap
  # 'repo' key cannot be defined before 'dapp' key (spark creds depend on this parsing rule)
  repo: https://github.com/dapfyi/uniswap-dapp.git
  branch: main

  # path to application folders (airflow, spark, superset, ...) from repository root
  path: .

  # install pipeline artefacts for listed apps
  apps:
  - airflow
  - spark
  - superset

  # last Docker image layer downloading this dapp's Airflow files:
  # - 'base' (default) performs a `git clone` for production grade and released pipelines
  # - 'hot' speeds up iteration cycles by pulling changes in a layer on top of 'base'
  #    -> typically, no more than one pipeline to build fast in this layer
  #    omit '-p base' flag of airflow/install.sh to benefit from this feature
  #
  airflow: base

  # - always 'base' in a first install from scratch, other installation profiles skip build steps:
  #    'base' will build the Spark version of the application from source (~30m if not in cache)
  #
  # - 'dep' installs system dependencies on top of base; typically s3 and delta:
  #    no reason not to skip 'dep' when skipping 'base', these layers should only be built once
  #
  # - 'default' will run the complete application build pulling the base image from registry:
  #    set 'default' on a first install if relying on an already built base, e.g.
  #        set build.baseImage to 'sparkubi-<version>' in the app values.yaml to build on it,
  #        (see the APP variable in dap/spark/sparkubi/config/VERSIONS for SparkUBI <version>)
  #        - this image is based on Spark default version within DaP -
  #
  # - 'hot' is an incremental build only pulling changes from git and applying them on 'default'
  #
  # - 'skip' deploys the app without any build step: complete build must be available in registry
  #
  spark: default
```

