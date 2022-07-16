# Configuration

**The selected set of configurations is under a single environment path defined by the ENV key.**

DaP supports three types of configuration in the given order of precedence:
1. environment variable for transient configuration: export `DaP_<Key>`\
*exception* - lowercase keys in table below cannot be overriden by an environment variable
2. local override outside version control:\
add value(s) in a file called `var` under your configuration path (next to the `default` file to override)\
*note* - the single value of uppercase keys must always be configured in a one-liner file
3. edit `DaP/<Path>/<Key>/default` to commit a new default value in your fork

*example available under CICD warning in bootstrap [README](/bootstrap)*

Path | Key | Values | Default | Description
--- | --- | --- | --- | ---
/ | ENV | `hack`, `demo` or `live` | `live` | configuration is read under the \<ENV> path of this variable
\<ENV> | BRANCH | remote branch of REPO or `_local` | `_local` checks the same branch as local git | `argocd app create --revision` argument 
\<ENV>/dapp | uniswap | parameters of DaP pipeline | `default` file in key path | `argo submit --parameter-file` argument of installer workflow
\<ENV> | REPO | URL of CD origin | `https://github.com/dapfyi/dap.git` | `argocd app create --repo` argument
\<ENV>/REPO/private | PRIVATE | `true` or `false` | `false` | switch to configure private repo authentication on new clusters
\<ENV>/REPO/private | SSH_KEY_NAME | private key file in local `~/.dap` folder | `deploy_key` | SSH key for CD from private repo
\<ENV> | SYNC | `none` or `auto` | `auto` | `argocd app create --sync-policy` argument 
\<ENV>/cluster | nodegroups | see semicolon separated [config](/DaP/live/cluster/nodegroups/default) | low limits of spot instances | eksctl mapping in `nodegroups` definition of bootstrap [script](/bootstrap/workflow/aws/blue-green-deployment.sh)
\<ENV>/cluster | PACK | `none` for a bare cluster or `etl` | `etl`: Airflow, Spark and Superset | "package" of pre-installed apps
\<ENV>/tag | DEBIAN | tag | `buster-20220228-slim` | OS of admin image
\<ENV>/version | ARGO_CD | version | `2.3.5` | upgrade [notes](./live/version/ARGO_CD)
\<ENV>/version | ARGO_WF_CHART | version | `0.16.7` | helm chart for Argo Workflows
\<ENV>/version | AWSCLI | version | `2.7.18` | aws cli [tags](https://github.com/aws/aws-cli/tags)
\<ENV>/version | EKSCTL | version | `0.86.0` | upgrade [notes](./live/version/EKSCTL)
\<ENV>/version | HELM | version | `3.9.2` | unmanaged helm for early bootstrap
\<ENV>/version | METRICS_SERVER | version | `0.6.1` | K8s autoscaling metrics
\<ENV>/version | KUBECTL | version | `1.21.10` | match K8s version in eksctl

