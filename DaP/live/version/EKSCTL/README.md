## Upgrade Notes

Watch out https://docs.aws.amazon.com/eks/latest/userguide/dockershim-deprecation.html next upgrade.\
Fluent Bit parser configuration could be impacted:
- from k8s 1.23, change docker Parser to cri in input-kubernetes.conf of Fluent Bit configmap (if not handled by chart)

Match k8s default version in eksctl with kubectl (one minor version difference with cluster tolerated).
1. look for "DefaultVersion" (pkg/apis/eksctl.io/v1alpha5/types.go file) in github eksctl release commit
2. pick matching kubectl version among tags https://github.com/kubernetes/kubectl/tags
3. set under parameter path DaP/\<ENV>/version/KUBECTL to align kubectl version across DaP
4. check Metrics Server compatibility [matrix](https://github.com/kubernetes-sigs/metrics-server#compatibility-matrix) every k8s upgrade in case of breaking changes

