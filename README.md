# DaP
DaP is an open platform to ingest, process and analyze Web3 data.

[Documentation](/doc) | [Deployment](/bootstrap)

### Features
- __Embedded Blockchain__ makes DaP fast and self-sufficient.
- __Data Pipeline__ from extraction to visualization: you develop it, DaP builds and runs it.
- __SQL Analytics__ powered by [SparkUBI](./spark/sparkubi): precise off-chain calculations at scale on Spark engine.
- and more...
    - __Token Prices__ at the historical live exchange rate on Uniswap;
    - *interfaces*: see screenshots and snippets on the gallery [page](https://trustless.land/gallery.html);
    - [repo](https://github.com/dapfyi/uniswap-dapp) showcasing advanced use cases in a plug-and-play pipeline.

### Technology
In technical terms, DaP is an OLAP system for Web3: 
> Online analytical processing (OLAP) uses complex queries to analyze aggregated historical data from OLTP systems.

For instance, [The Graph](https://thegraph.com/en/) is an OLTP system for Web3:
> Online transaction processing (OLTP) captures, stores, and processes data from transactions in real time.

While they both serve queries, OLAP requires a different architecture for analytics than OLTP for web applications. The former optimizes higher throughput of arbitrary computations and the latter lower latency of pre-defined logic.

### Limits
Like any OLAP solution, DaP trades off multi-tenancy for scale and responsiveness for bandwidth, i.e.
- APIs are not designed to be exposed publicly;
- best latency such a system can achieve is near real-time (seconds vs milliseconds in OLTP).

## Stack
DaP runs in AWS on a Data Lakehouse architecture, enabling BI and ML in a single system supporting ACID transactions. Much of the development work has gone into the integration, specialization and automation of awesome open-source projects.

- DaP has been made possible by [K8s](https://github.com/kubernetes/kubernetes), [Geth](https://github.com/ethereum/go-ethereum), [Uniswap](https://uniswap.org/), [Airflow](https://github.com/apache/airflow), [Spark](https://github.com/apache/spark) & [Superset](https://github.com/apache/superset).
- It's been automated with tools like [CloudFormation](https://aws.amazon.com/cloudformation/), [eksctl](https://github.com/weaveworks/eksctl), [Argo CD](https://github.com/argoproj/argo-cd), [Kaniko](https://github.com/GoogleContainerTools/kaniko) & good old bash.

*Note*: all sources used under their own respective licenses.
> Should parts of this repo not already be covered by a parent project and despite significant exceptions (go-ethereum under GNU LGPLv3), DaP is governed by the Apache License 2.0 like most of its stack.
## Highlights
- **Infrastructure** - _You create or you delete, unless you develop._

Imperative configuration has been made immutable with system-wide blue-green deployment. It reduces maintenance by removing the need to manage state drift where declarative manifests do not work. No effort is spent handling updates. Another system version can be easily bootstrapped from scratch in parallel. Development always happen on a clean slate and no environment is subpar.
- **Data Extraction** - _Scalable data lake feed._

Ingesting historical events from smart contracts scales with processors available to an integrated Ethereum client. Computing capacity is decoupled from blockchain state and can be resized on demand. On the server side, Airflow workers required for orchestration and post-processing can be left entirely managed by K8s autoscaler.
- **Processing** - _Off-chain computation engine._

Apache Spark has been extended with a custom plugin enabling the seamless processing of big blockchain integers. The accurate valuation of transactions and tokens benefits from native Spark performance. See [SparkUBI](/spark/sparkubi/README.md) for more info.
- **Data Pipelines** - _Environment as a service._

Build and deploy Web3 data pipelines in a PaaS fashion from a git repo ([example](https://github.com/dapfyi/uniswap-dapp)). DaP aims to provide savvy engineers with the ease-of-use of a managed service in an open system. It supports orchestrated ETL or ML processes, all the way to SQL analytics, visualization and dashboards.

