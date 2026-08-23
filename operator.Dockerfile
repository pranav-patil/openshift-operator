# Build the manager binary
FROM quay.io/operator-framework/helm-operator:v1.41.1

ARG SEMVER
ARG HELM_CHART_VERSION
ARG COMMIT_SHA

LABEL name="zyron-containersecurity"
LABEL maintainer="Emprovise Inc <support@emprovise.com>"
LABEL vendor="Emprovise Inc"
LABEL version=$SEMVER
LABEL release=$SEMVER
LABEL summary="Emprovise™ KubeWatch"
LABEL description="Emprovise™ KubeWatch delivers full lifecycle protection for containers with real-time threat detection, policy enforcement, compliance assurance, and rapid incident response."
LABEL io.k8s.display-name="Emprovise™ KubeWatch v${SEMVER}"
LABEL io.k8s.description="Emprovise™ KubeWatch."
LABEL io.openshift.tags=hpe,csi,hpe-csi-driver,storage
LABEL helm.charts.container_security.version=${HELM_CHART_VERSION}
LABEL operator.commit.sha=${COMMIT_SHA}

ENV HOME=/opt/helm
COPY watches.yaml ${HOME}/watches.yaml
COPY helm-charts  ${HOME}/helm-charts
COPY LICENSE /licenses/
WORKDIR ${HOME}
