## Upgrade Notes

Watch out https://docs.aws.amazon.com/eks/latest/userguide/dockershim-deprecation.html next upgrade.\
Fluent Bit installation and parser configuration could be impacted:
- rbac.authorization.k8s.io/v1beta1 ClusterRole -> v1 in 1.22+
- rbac.authorization.k8s.io/v1beta1 ClusterRoleBinding -> v1 in v1.22+
- from k8s 1.23, change docker Parser to cri in input-kubernetes.conf of Fluent Bit configmap

Match k8s default version in eksctl with kubectl (one minor version difference with cluster tolerated).
1. look for "DefaultVersion" (pkg/apis/eksctl.io/v1alpha5/types.go file) in github eksctl release commit
2. pick matching kubectl version among tags https://github.com/kubernetes/kubectl/tags
3. set under parameter path DaP/\<ENV>/version/KUBECTL to align kubectl version across DaP

