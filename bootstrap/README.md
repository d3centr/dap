# Deployment
**WARNING**: CICD is automatically active on main branch. To avoid hacks or unattended updates of processes with access to an Ethereum node, you are advised to fork this repo and change its reference URL with your own address before you deploy any app.

Pick **one** of the 4 options given below, in order of precedence:
> 0) you can simply disable automated sync by exporting `DaP_SYNC`=`none` before install scripts;

Note: SYNC also supports _var_ and _default_ file configuration as described below for REPO; more info in [DaP](/DaP).
> 1) export `DaP_REPO`=`https://github.com/<my account>/dap.git` for transient configuration;
> 2) for local override outside version control: add your repo URL to a file called `var` in `DaP/live/REPO`;
> 3) edit DaP/live/REPO/[default](/DaP/live/REPO/default) to change the default repo in your fork.

By default, Argo CD will pull and apply live app changes from `https://github.com/dapfyi/dap.git`.

--------------------------------------------------------------------------------------------------

*Optional*: to set up app installs from a private repo before a cluster bootstrap,\
review configuration of `REPO/PRIVATE` and `.../SSH_KEY_NAME` in [DaP](/DaP).\
You can always follow Argo CD [instructions](https://argo-cd.readthedocs.io/en/stable/user-guide/private-repositories/) to set up private repos later and manually.

0. **Requirements**: admin rights in the cloud + a bash shell with docker and aws clis configured locally.\
Run `aws configure` and specify region where DaP will be deployed or export `$AWS_PROFILE` to an existing configuration previously specified with `aws configure --profile <DaP AWS profile name>` (if not default).

1. Create **Network** and deploy **Geth** node in this order from [client](/client) folder.

2. **K8s** provides computing capacity with autoscaling. Run `./deploy.sh` in this folder to create a cluster ready for applications. Process should take around 20 minutes. You can run `./destroy.sh` to delete the cluster when computation isn't required. Note: as a rule of thumb, state is externalized but applications are expected to be re-installed on any new cluster.

## Admin

*proceed with 3. and 4. ONLY if you'd like to manually manage apps installed on DaP clusters*\
If you do, you might also want to disable the automated installation of apps on new clusters: set `DaP/<ENV>/cluster/PACK` to `none`.

3. Transient containers isolate the runtime of a DaP **cluster administration** from your local machine. Above script `./deploy.sh` will first build a docker image locally. You need to load a function called `dap` into your shell to wrap the call to `docker run`. `dap` executes commands in a compatible and versioned docker environment. Simply source `runtime.sh` in this directory to load `dap` function into your shell: `. runtime.sh`.

4. **Applications** to be installed on top of k8s are found in other modules. 3 scripts help to manage a release lifecycle from each top-level application folder. Make it your working directory to execute scripts:
- `dap ./pre-install.sh` sets up dependencies and plugs in stateful resources that outlive a cluster.
- `dap ./install.sh` delegates the job to Argo CD where you can follow in the UI - refer to App UI section in [client](/client).
- `./cleanup.sh` is only called at your discretion to delete dependencies created by pre-install outside k8s.

### Example

By default, the walkthrough below is automated. It illustrates the process to manually install apps.

```bash
# deploy cluster assuming that DaP network already exists (1.)
cd boostrap
./deploy.sh  # takes 20m or so

# deploy superset app on DaP cluster
. runtime.sh  # load dap function into you shell
cd ../superset  # working directory contextualizes instructions sent to DaP cluster
dap ./pre-install.sh  # must be run once on new clusters, e.g. add any persistent volume to K8s
dap ./install.sh  # asynchronous call, see Argo CD for status
```

