*keep the same AWS region configured across DaP modules*

### Create Network
`./stack.sh network.yaml`

### Deploy Geth
```
aws cloudformation create-stack --stack-name dap-geth --template-body file://geth.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=InstanceSize,ParameterValue=xlarge
```

Replace `create` by `update` to deploy template or parameter changes: `aws cloudformation update-stack ...`. Values of previous configuration can be kept by overriding template defaults with parameters like `ParameterKey=NetRestrict,UsePreviousValue=true`.

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
Superset | superset.example.com | `... -n superset svc/superset 8088`

<sup>1</sup> on green clusters, add 2 to subdomain: e.g. airflow2.example.com or cd2.example.com

