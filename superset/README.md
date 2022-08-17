## Dependencies

Superset depends on a metastore for table metadata and a Spark SQL server/cluster to execute queries.\
These dependencies are provided by `spark/sparkubi` app.

When automated installation of applications is disabled...

*from spark directory*
- install Sparkubi app:\
 `./install.sh -a sparkubi -p skip` (skip profile excludes the build stage)

### Memory/CPUs/Executors
Add `-c <config name>` above to set non-default resources loaded from `spark/sparkubi/config`.

*Note*: when a new configuration is applied to a running sparkubi app, `sparkubi-thrift` job in `spark` namespace must then be deleted for changes to take effect. This will restart Spark Thrift Server through `sts-controller` in sparkubi chart.

## Dashboard export/import

Export dashboards from cli to import from cli or stick to the UI to avoid incompatibilities.

### CLI export/import

- store pod name in a variable
```
pod=`kubectl get pod -n superset -l app=superset -o jsonpath='{.items[*].metadata.name}'`
```
- export
```
kubectl exec -n superset $pod -- superset export-dashboards -f export.zip
kubectl cp superset/$pod:/app/export.zip /tmp/export.zip
```
- import
```
kubectl cp /tmp/export.zip superset/$pod:/app/export.zip
kubectl exec -n superset $pod -- superset import-dashboards -p export.zip
```

