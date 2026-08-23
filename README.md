# Openshift Operator

Container Security Operator for deployment of [Zyron-Container-Security-Helm](https://github.com/emprovise/zyron-container-security-helm) on Red Hat OpenShift.

## Prerequisites

- Requires OpenShift Cluster for testing. Refer [OpenShift Rosa](https://emprovise.atlassian.net/wiki/spaces/TPAT/pages/785681527/Openshift+Cluster+with+ROSA) or [Openshift Dedicated](https://emprovise.atlassian.net/wiki/spaces/TPAT/pages/852498209/OpenShift+Dedicated+Cluster+Setup) Cluster setup docs.
- Install [Docker](https://www.docker.com/) or [Podman](https://podman.io/) Container Tool
  - Install Docker based on Operating System ([Linux](https://docs.docker.com/engine/install/), [Windows](https://docs.docker.com/desktop/setup/install/windows-install/), [Mac](https://docs.docker.com/desktop/setup/install/mac-install/)). Ensure docker instance is running using below command.

        docker info
  
  - Install [Podman](https://podman.io/docs/installation) based on the Operating System. After installation create and start the Podman machine as below:

        podman machine init
        podman machine start
        podman info

    Shutdown Podman machine after running preflight checks.

        podman machine stop

- kubectl and [OpenShift](https://access.redhat.com/downloads/content/290/ver=4.19/rhel---9/4.19.0/x86_64/product-software) command-line tool installed and configured to connect to your OpenShift cluster
- [operator-sdk](https://sdk.operatorframework.io/docs/installation/) is installed to create/validate Operator Bundle

## Install Operator

1. Login into your OpenShift cluster and ensure you can access the cluster using `oc get nodes`:

       oc login https://api.<YOUR_OPENSHIFT_CLUSTER_ID>.vw97.p1.openshiftapps.com:6443 --username cluster-admin --password <YOUR_PASSWORD>

2. OpenShift cluster install OLM by default. If OLM not present then ensure OLM is installed using below command:

       operator-sdk olm install

3. Ensure that `opm` CLI is [installed](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/cli_tools/opm-cli#cli-opm-install) which is provided by the Operator Framework for use with the Operator bundle format:

       make opm
       export PATH="$PWD/bin:$PATH"

4. The Load Helm Chart command without the `HELM_CHART_VERSION` argument, downloads the latest version of [Zyron-Container-Security-Helm](https://github.com/emprovise/zyron-container-security-helm) helm chart in `helm-charts` directory. The below command sets the `HELM_CHART_VERSION` environment variable.

       export $(make load-helm-chart)

   We can also specify which version of V1-Container-Security helm chart to download by passing `HELM_CHART_VERSION` argument.

       make load-helm-chart HELM_CHART_VERSION=<CONTAINER_SECURITY_HELM_VERSION>

5. Create `emprovise-system` namespace:

       kubectl create ns emprovise-system

6. Setup ZyronContainerSecurity and ZyronContainerSecurityBundle repositories either public or private using AWS ECR. Local Docker repository will not work. If using private AWS ECR repository get AWS token, create AWS ECR secret, link to service-account, and set `ZCS_OPERATOR_BASE_IMG_URL` environment variable (base repository URI) for AWS ECR, e.g. `${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/container-security` to pull operator/bundle/catalog images. For public docker repository set the `ZCS_OPERATOR_BASE_IMG_URL` correspondingly e.g. `docker.io/emprovise`.

       export AWS_ACCOUNT_ID=198890578717
       export AWS_REGION=us-east-1
       export ZCS_OPERATOR_BASE_IMG_URL=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/container-security

       aws sts get-caller-identity --region ${AWS_REGION}

       aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

       oc delete secret docker-registry ecr-secret -n emprovise-system --ignore-not-found

       oc create secret docker-registry ecr-secret \
       --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
       --docker-username=AWS \
       --docker-password=$(aws ecr get-login-password --region ${AWS_REGION}) \
       --docker-email=support@emprovise.com \
       -n emprovise-system

       oc secrets link default ecr-secret --for=pull -n emprovise-system
       

7. Add default fallback container policy to accept all images (without signature) if no specific match is present for container tool (docker, podman). 

        make add-container-policy

8. Export the ContainerSecurity Operator version using `OPERATOR_VERSION` environment variable e.g. `0.0.5`. Also export Zyron Bootstrap Token as environment variable to connect to zyron which will be used to create `zyroncontainersecurity-sample` [operator instance](#install-container-security-helmchart-using-operator).

       export OPERATOR_VERSION=<YOUR_ZCS_OPERATOR_VERSION>

       export BOOTSTRAP_TOKEN=<YOUR_BOOTSTRAP_TOKEN>

9. Add Zyron integration environment endpoint URL for testing using `zyroncontainersecurity-sample` (default endpoint is for production).

       export V1_ENDPOINT=https://api-int.zyron.emprovise.com/external/v2/direct/vcs/external/vcs

10. Substitute the environment variables in the operator config YAML files, keeping the original YAML templates files as backup using `*.bak` or in `tmp/*.bak`.

        make clean ignore=catalog subst

11. Build ZyronContainerSecurity Operator, Bundle and Catalog docker images. If the Operator/Bundle/Catalog images are already present in Container Repository for the provided `OPERATOR_VERSION` then skip this step.<br/><br/>
     a. [**FOR NON-LINUX MACHINE**] Multi-platform docker images using `buildx`:

        make operator-buildx bundle bundle-buildx catalog-buildx

     b. [**FOR LINUX MACHINE ONLY**] Machine platform docker images using `build`:

        make operator-build operator-push
        make bundle bundle-build bundle-push
        make catalog-build catalog-push

12. Install the operator using below command which will create the operator group, CatalogSource and subscription.

        kubectl apply -k config/olm

### Install Script

Use the below installation shell script to install Operator **after completing step 8**.

       sh scripts/install.sh

For multi-platform operator build use below install shell script command.

       sh scripts/install.sh -multi-platform

## Upgrade Operator

In order to upgrade the OpenShift Operator we repeat subset of above steps again:
- Export new value of `OPERATOR_VERSION` env variable using `export OPERATOR_VERSION=<YOUR_ZCS_OPERATOR_VERSION>`.
- Execute `make clean ignore=catalog subst`.
- Build and Push Operator, Bundle and Catalog docker images (follow step 11).
- Upgrade the operator using `kubectl apply -k config/olm`.

**NOTE: By default `CATALOG_MODE` is `fbc` ([File Based Catalog](https://olm.operatorframework.io/docs/reference/file-based-catalogs/) using [Basic Catalog Template](https://olm.operatorframework.io/docs/reference/catalog-templates/#basic-template)). If the `CATALOG_MODE` is set to [deprecated](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/cli_tools/opm-cli#opm-cli-ref-index_cli-opm-ref) `sqlite` format then upgrading the operator would require to export the previous ContainerSecurity Operator version as `PREVIOUS_OPERATOR_VERSION` environment variable**. 

       export PREVIOUS_OPERATOR_VERSION=<YOUR_PREVIOUS_ZCS_OPERATOR_VERSION>


## Install Container-Security HelmChart using Operator

Create example ZyronContainerSecurity instance named `zyroncontainersecurity-sample` which will install ZyronContainerSecurity Operator's Helm Charts.

       kubectl apply -f config/samples/zyron-containersecurity-sample.yaml

Alternatively you can go to OpenShift Administrative Console (using `https://console-openshift-console.apps.<YOUR_OPENSHIFT_CLUSTER_ID>.<YOUR_SUBDOMAIN>.p1.openshiftapps.com`) to install Helm chart using operator.
- On left hand panel of OpenShift Admin Console, select `Operators` and then `Installed Operators`. This will open `Installed Operators` page.
- In the search by name box on Installed Operators page type `ZyronContainerSecurity`. Click on the ZyronContainerSecurity installed operator link.
- On the top Menu of the ZyronContainerSecurity Operator, click on `ZyronContainerSecurity` which is last item on the Menu. This will show the list of `ZyronContainerSecurity` operators installed on the OpenShift cluster.
- To create new ContainerSecurity Helm Chart instance on the cluster using the operator, click `Create ZyronContainerSecurity` button on far right side.
- Fill in the form including the `Zyron` details (click `>` on right to expand form) which contains; bootstrapToken, endpoint, exclusion and other support arguments parameters i.e. inventoryCollection, malwareScanning, runtimeSecurity, secretScanning, vulnerabilityScanning.
- Once form is completed click on `Create` at the bottom for the form to install Container-Security HelmChart using Operator.


   ![List ZyronContainerSecurity](images/operator-install.png)

   ![Create ZyronContainerSecurity Form](images/operator-install-form.png)


## Score Card Tests

       operator-sdk scorecard "${ZCS_OPERATOR_BASE_IMG_URL}/zyron-containersecurity-bundle:v${OPERATOR_VERSION}" --namespace emprovise-system


## Preflight Checks

[Preflight](https://github.com/redhat-openshift-ecosystem/openshift-preflight) is a command line (CLI) tool to verify that partner-submitted containers meet minimum requirements for Red Hat Software Certification. [Install Preflight CLI](https://github.com/redhat-openshift-ecosystem/openshift-preflight/blob/main/README.md#Installation) using below command:

      go install github.com/redhat-openshift-ecosystem/openshift-preflight/cmd/preflight@latest

The preflight utility allows to confirm that container and Operator projects comply with container and Operator certification policies.
We use the below commands to run [preflight checks](https://github.com/redhat-openshift-ecosystem/openshift-preflight/blob/main/docs/CONFIG.md) on Operator.

      aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

      export KUBECONFIG=~/.kube/config
      export PFLT_DOCKERCONFIG=~/.docker/config.json
      export PFLT_SCORECARD_WAIT_TIME=600
      export PFLT_LOGLEVEL=trace
      export PFLT_ARTIFACTS=preflight_results
      export PFLT_LOGFILE=/preflight_results/preflight.log
      export PFLT_INDEXIMAGE=${ZCS_OPERATOR_BASE_IMG_URL}/zyron-containersecurity-catalog:v${OPERATOR_VERSION}

      preflight check operator ${ZCS_OPERATOR_BASE_IMG_URL}/zyron-containersecurity-bundle:v${OPERATOR_VERSION}


## Uninstall Operator

> ⚠️ **WARNING**  
> **Remove all Operator Instances (Helm charts) installed _before_ deleting the Operator.**

1. Delete all `ZyronContainerSecurity` Custom Resources. If created manually using YAML file use below command with corresponding YAML file, if created from OpenShift Admin Console then delete from the UI as shown below:

       kubectl delete -f config/samples/zyron-containersecurity-sample.yaml


   ![Delete ZyronContainerSecurity](images/operator-delete.png)


2. Delete the Custom Resource Definition (CRD):

       kubectl delete -f config/crd/bases/container-security.emprovise.com_zyroncontainersecurities.yaml

3. Uninstall the zyron-containersecurity operator using below commands. This deletes the OperatorGroup, CatalogSource, Subscription and ClusterServiceVersion.

       kubectl delete -k config/olm
       kubectl delete csv zyron-containersecurity.v${OPERATOR_VERSION} -n emprovise-system

4. Delete `emprovise-system` namespace:

       kubectl delete namespace emprovise-system

5. Clean ZyronContainerSecurity file resources:
    
       make clean

### Cleanup Script

Use the below uninstall shell script to clean up Operator resources from previous installations.

       sh scripts/uninstall.sh
