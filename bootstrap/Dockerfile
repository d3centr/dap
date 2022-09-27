ARG DEBIAN_TAG
FROM debian:$DEBIAN_TAG
SHELL ["/bin/bash", "-o", "pipefail", "-e", "-u", "-x", "-c"]

ARG AWSCLI_VERSION
ARG EKSCTL_VERSION
ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG ARGO_CD_VERSION
ARG ARGO_WF_CHART_VERSION
ENV KUBECTL_VERSION $KUBECTL_VERSION

# gettext-base installs envsubst command
RUN apt-get update && apt-get install -y curl unzip gettext-base git && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64-$AWSCLI_VERSION.zip -o awscliv2.zip && \
    unzip awscliv2.zip && ./aws/install && rm awscliv2.zip
ENV AWS_PAGER=

RUN curl -L https://github.com/weaveworks/eksctl/releases/download/v$EKSCTL_VERSION/eksctl_Linux_amd64.tar.gz | \
    tar xz -C /usr/local/bin

RUN curl -LO https://dl.k8s.io/release/v$KUBECTL_VERSION/bin/linux/amd64/kubectl && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

RUN curl https://get.helm.sh/helm-v$HELM_VERSION-linux-amd64.tar.gz | tar xz -C /tmp && \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm && rm -r /tmp/linux-amd64 && \
    helm repo add argo https://argoproj.github.io/argo-helm

RUN WF_APP=`helm search repo argo-workflows --version $ARGO_WF_CHART_VERSION -o json | grep -oP '(?<=app_version":"v)[0-9.]+'` && \
    curl -LO https://github.com/argoproj/argo-workflows/releases/download/v$WF_APP/argo-linux-amd64.gz && \
    gunzip argo-linux-amd64.gz && chmod +x argo-linux-amd64 && mv ./argo-linux-amd64 /usr/local/bin/argo

RUN curl -L -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v$ARGO_CD_VERSION/argocd-linux-amd64 && \
    chmod +x /usr/local/bin/argocd

