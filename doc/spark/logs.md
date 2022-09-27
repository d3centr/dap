## Spark Logs

Fluent Bit must be deployed from `log` folder to persist logs in s3.

You can then explore logs from SQL Lab in Superset, e.g.

- *create temporary table*
```sql
-- replace <LOG_BUCKET> with actual bucket name in your environment
CREATE TEMPORARY TABLE log USING json LOCATION 's3://<LOG_BUCKET>/fluent-bit'
```
- *retrieve error messages from Spark executors*
```sql
-- query partitions date, namespace and pod for efficient retrieval
SELECT log FROM log 
WHERE date = '2022-10-19' AND namespace = 'spark' AND pod LIKE '%-exec-%' 
AND log LIKE '%ERROR%'
```
- *correlate errors of driver and executor logs, with stack trace*
```sql
SELECT min(time), first(pod), first(log)           -- remove dupes
FROM log                                           -- table defined earlier
WHERE date = '2022-10-19' AND namespace = 'spark'  -- filter partitions
AND (pod LIKE '%-submit-%'                         -- driver logs 
    AND log RLIKE 'ERROR|Caused by: |^[^a-z]at '   -- errors + stack trace
    AND log NOT LIKE '%org.apache.spark%')         -- remove clutter
OR (pod LIKE '%-exec-%'                            -- correlate w/ executors
    AND log LIKE '%ERROR root%')                   -- root logger only
GROUP BY pod, log ORDER BY 1                       -- order of first occurrence
```

