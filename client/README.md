*keep the same AWS region configured across DaP modules*

### Create Network
`./stack.sh network.yaml`

### Deploy Prysm
`./stack.sh prysm.yaml` (`InstanceSize=xlarge` default)

On a **first deployment**, database won't be backed in s3. You might want to:
1) add `InstanceSize=2xlarge` argument to the command above to speed up initial sync;
2) wait for Prysm to sync until the merge before deploying the execution client.

On a **subsequent launch** or update, you might want to:
1) add `EnableBackup=true` argument to sync blockchain data between client and backup before the former starts;
2) scale down instance size to `large` if you caught up with the chain and wish to simply keep it in sync;
3) set `EnableBackup=false` to avoid automated backup sync whenever a spot instance reboots (causing downtime).

*all these parameters won't have any effect if the instance size isn't explicitly changed at the same time*

> If you wish to deploy Lighthouse beacon client instead, you need to bring your own knowledge, e.g:\
Lighthouse does not sync before the merge without an execution client, etc...

### Deploy Geth
`./stack.sh geth.yaml`
- the same command can update an existing stack, Key=value parameters are optional:\
`./stack.sh geth.yaml InstanceSize=xlarge BeaconClient=prysm EnableBackup=false  # showing default values`

**Caveat**: change `InstanceSize` to force a version upgrade in a running client.\
You will always be prompted to confirm the version of a client to install.

*monitoring blockchain clients*

- Dashboards are available in Grafana. They require a running DaP cluster.
- A shell can also be opened on nodes: select the instance in EC2 console and connect with Session Manager.
```bash
sudo su  # get rights to access system logs
cat /var/log/cfn-init.log  # shows how bootstrap steps went
cat /var/log/bootstrap.log  # see logs inside those steps (debug)
journalctl -u client -fo cat  # watch client logs
geth attach /mnt/data/mainnet/geth.ipc  # open geth console
```
**Tip**: in geth console, `debug.vmodule('rpc=5')` activates RPC debug logs.

### DaP Domain
*optional but convenient*

Allow authenticated users to access DaP through a custom and secure URL.

**Requirement**: a public hosted zone of your domain must already exist in Route 53.

Replace occurrences of `example.com` below by your own domain.
1. Create a user pool, a client, certificates and email service for your domain:\
`./stack.sh domain.yaml example.com`.\
Note: a domain stack must be deployed for each DaP region - user pools are not global.

2. Set [DaP](/DaP) keys INGRESS to `true` and DOMAIN to `example.com` before you deploy a cluster.

3. Go through `./signup.sh` prompts to create your credentials.\
Tip: have a TOTP app handy to set up required 2FA before expiry of the authorized session.

### Application UI
They are two ways to access an application UI running on a DaP cluster:
- either set up a DaP Domain for direct URL access as described above (recommended)
- or port forward ports through your local machine (development/debugging).

UI | Subdomain (blue<sup>1</sup>) | `kubectl port-forward ...`
--- | --- | ---
Airflow | airflow.example.com | `... -n airflow svc/airflow-webserver 8080`
Argo CD | cd.example.com | `... -n argocd svc/argocd-server 8081:80`
Argo Workflows | argo.example.com | `... -n argo svc/wf-argo-workflows-server 2746`
Grafana | grafana.example.com | `... -n monitor svc/monitor-grafana 8082:80`
Spark Thrift Server | sts.example.com | `... -n spark svc/sparkubi-thrift 4040`
Superset | superset.example.com | `... -n superset svc/superset 8088`

<sup>1</sup> on green clusters, add 2 to subdomain: e.g. airflow2.example.com or cd2.example.com

