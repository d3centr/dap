## Dependencies

Superset depends on a metastore for table metadata and a Spark SQL server/cluster to execute queries.

*from spark directory*
- install the Hive metastore in Sparkubi app:\
 `./install.sh -a sparkubi -p skip` (skip profile excludes the build stage)
- run Thrift server `./submit.sh sparkubi thrift`: light default resource configuration\
or use config flag, e.g. `-c mining`, after `./submit.sh` to allocate more resources

Resource configuration is loaded from a file name in `spark/sparkubi/config`.

## Dashboard export/import

Note: export dashboards from cli to import from cli or stick to the UI to avoid incompatibilities.

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

