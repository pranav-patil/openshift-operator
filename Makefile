# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.39.2

# Supported List of OpenShift Versions
# This variable is used to define the OpenShift versions that the operator supports.
SUPPORTED_OPENSHIFT_VERSIONS ?= "v4.12-v4.20"

# PLATFORMS defines the target platforms for  the manager image be build to provide support to multiple
# architectures. (i.e. make operator-buildx IMG=myregistry/mypoperator:0.0.2). To use this option you need to:
# - able to use docker buildx . More info: https://docs.docker.com/build/buildx/
# - have enable BuildKit, More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image for your registry (i.e. if you do not inform a valid value via IMG=<myregistry/image:<tag>> than the export will fail)
# To properly provided solutions that supports more than one platform you should use this option.
PLATFORMS ?= linux/arm64,linux/amd64

# bundle channels
CHANNELS ?= alpha,stable
DEFAULT_CHANNEL ?= stable
FAST_CHANNEL ?= alpha

LOCAL ?= $(shell pwd)
LOCAL_BIN ?= $(LOCAL)/bin
BIN_DIR ?= /usr/local/bin

OS := $(shell uname | tr '[:upper:]' '[:lower:]')
ARCH_RAW := $(shell uname -m)
ARCH := $(shell \
	if [ "$(ARCH_RAW)" = "x86_64" ]; then echo "amd64"; \
	elif [ "$(ARCH_RAW)" = "aarch64" ] || [ "$(ARCH_RAW)" = "arm64" ]; then echo "arm64"; \
	else echo "unsupported"; fi)

# Supported Catalog modes are:
# - fbc: File-based catalog (default)
# - sqlite: SQLite-based catalog (deprecated)
CATALOG_MODE ?= fbc

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# emprovise.com/zyron-containersecurity-bundle:$VERSION and emprovise.com/zyron-containersecurity-catalog:$VERSION.
IMAGE_TAG_BASE ?= ${ZCS_OPERATOR_BASE_IMG_URL}/zyron-containersecurity

# OPERATOR_IMG defines the image:tag used for the operator.
# You can use it as an arg. (E.g make operator-build OPERATOR_IMG=<some-registry>/<project-name-operator>:<tag>)
OPERATOR_IMG ?= $(IMAGE_TAG_BASE)-operator:v${OPERATOR_VERSION}

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:v${OPERATOR_VERSION}

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version ${OPERATOR_VERSION} $(BUNDLE_METADATA_OPTS)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Image URL to use all building/pushing image targets
IMG ?= controller:latest

# Macro to push an image and also tag/push the ":latest" variant
define docker_push
	$(CONTAINER_TOOL) push $(1)
	echo "Pushed image $(1)"
	@if [ -n "$$($(CONTAINER_TOOL) images -q $(subst :v$(OPERATOR_VERSION),:latest,$(1)))" ]; then \
		$(CONTAINER_TOOL) push $(subst :v$(OPERATOR_VERSION),:latest,$(1)); \
		echo "Pushed image $(subst :v$(OPERATOR_VERSION),:latest,$(1))"; \
	fi
endef

.PHONY: all
all: operator-build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

.PHONY: run
run: helm-operator ## Run against the configured Kubernetes cluster in ~/.kube/config
	$(HELM_OPERATOR) run

COMMIT_SHA := $(shell git rev-parse HEAD)
LATEST_OPERATOR_TAG = $(subst :v$(OPERATOR_VERSION),:latest,$(OPERATOR_IMG))
ADD_LATEST_TAG ?= false

.PHONY: operator-build
operator-build: ## Build docker image with the manager.
	@echo "Building ${CONTAINER_TOOL} operator image for operator version ${OPERATOR_VERSION}, helm chart version ${HELM_CHART_VERSION} and commit ${COMMIT_SHA}"; \
	$(CONTAINER_TOOL) build --build-arg SEMVER=${OPERATOR_VERSION} --build-arg HELM_CHART_VERSION=${HELM_CHART_VERSION} --build-arg COMMIT_SHA=${COMMIT_SHA} -t ${OPERATOR_IMG} $(if $(filter true,$(ADD_LATEST_TAG)),-t $(LATEST_OPERATOR_TAG),) -f operator.Dockerfile .

.PHONY: operator-buildx
operator-buildx: ## Build and push docker image for the manager for cross-platform support
	@echo "Building docker operator image for operator version ${OPERATOR_VERSION}, helm chart version ${HELM_CHART_VERSION} and commit ${COMMIT_SHA}"; \
	if [ "$(CONTAINER_TOOL)" = "docker" ]; then \
		docker buildx create --name operator-builder --driver docker-container --use; \
		docker buildx build --no-cache --build-arg SEMVER=${OPERATOR_VERSION}  --build-arg HELM_CHART_VERSION=${HELM_CHART_VERSION} --build-arg COMMIT_SHA=${COMMIT_SHA} --push --platform=$(PLATFORMS) --tag ${OPERATOR_IMG} $(if $(filter true,$(ADD_LATEST_TAG)),-t $(LATEST_OPERATOR_TAG),) -f operator.Dockerfile .; \
		docker buildx rm operator-builder; \
	elif [ "$(CONTAINER_TOOL)" = "podman" ]; then \
		podman manifest rm $(OPERATOR_IMG) || true; \
		podman build --build-arg SEMVER=${OPERATOR_VERSION}  --build-arg HELM_CHART_VERSION=${HELM_CHART_VERSION} --build-arg COMMIT_SHA=${COMMIT_SHA} --platform $(PLATFORMS) $(if $(filter true,$(ADD_LATEST_TAG)),-t $(LATEST_OPERATOR_TAG),) --manifest $(OPERATOR_IMG) -f operator.Dockerfile .; \
		podman manifest push --all $(OPERATOR_IMG); \
	else \
		echo "Error: Unsupported container tool: $(CONTAINER_TOOL)."; \
		exit 1; \
	fi

.PHONY: operator-push
operator-push: ## Push the operator image.
	$(call docker_push,$(OPERATOR_IMG))

##@ Deployment

.PHONY: install
install: kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

.PHONY: deploy
deploy: kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/default | kubectl delete -f -

KUSTOMIZE_VERSION := $(shell curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep '"tag_name":' | sed -E 's/.*"kustomize\/(v[0-9.]+)".*/\1/')

.PHONY: kustomize
KUSTOMIZE = $(LOCAL_BIN)/kustomize
kustomize: ## Download kustomize locally if necessary.
ifeq (,$(wildcard $(KUSTOMIZE)))
ifeq (,$(shell which kustomize 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(KUSTOMIZE)) ;\
	curl -sSLo - https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/$(KUSTOMIZE_VERSION)/kustomize_$(KUSTOMIZE_VERSION)_$(OS)_$(ARCH).tar.gz | \
	tar xzf - -C bin/ ;\
	}
else
KUSTOMIZE = $(shell which kustomize)
endif
endif

.PHONY: helm-operator
HELM_OPERATOR = $(LOCAL_BIN)/helm-operator
helm-operator: ## Download helm-operator locally if necessary, preferring the $(pwd)/bin path over global if both exist.
ifeq (,$(wildcard $(HELM_OPERATOR)))
ifeq (,$(shell which helm-operator 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(HELM_OPERATOR)) ;\
	curl -sSLo $(HELM_OPERATOR) https://github.com/operator-framework/operator-sdk/releases/download/v1.39.2/helm-operator_$(OS)_$(ARCH) ;\
	chmod +x $(HELM_OPERATOR) ;\
	}
else
HELM_OPERATOR = $(shell which helm-operator)
endif
endif

.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCAL_BIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$(OS)_$(ARCH) ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

.PHONY: bundle
bundle: kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	cp config/manager/kustomization.yaml config/manager/kustomization.yaml.bak
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(OPERATOR_IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(MAKE) set-openshift-annotations
	$(OPERATOR_SDK) bundle validate ./bundle --select-optional name=operatorhubv2 --optional-values=k8s-version=1.26
	$(OPERATOR_SDK) bundle validate ./bundle --select-optional suite=operatorframework --optional-values=k8s-version=1.26

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	$(CONTAINER_TOOL) build --no-cache --build-arg SEMVER=${OPERATOR_VERSION} -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-buildx
bundle-buildx: ## Build the bundle image for multiple supported platforms.
	@if [ "$(CONTAINER_TOOL)" = "docker" ]; then \
		docker buildx create --name operator-bundle-builder --driver docker-container --use; \
		docker buildx build --no-cache --build-arg SEMVER=${OPERATOR_VERSION} --platform=$(PLATFORMS) -f bundle.Dockerfile -t $(BUNDLE_IMG) --push .; \
		docker buildx rm operator-bundle-builder; \
	elif [ "$(CONTAINER_TOOL)" = "podman" ]; then \
		podman manifest rm $(BUNDLE_IMG) || true; \
		podman build --build-arg SEMVER=${OPERATOR_VERSION} --platform $(PLATFORMS) -t $(BUNDLE_IMG) --manifest $(BUNDLE_IMG) -f bundle.Dockerfile .; \
		podman manifest push --all $(BUNDLE_IMG) docker://$(BUNDLE_IMG); \
	else \
		echo "Error: Unsupported container tool: $(CONTAINER_TOOL)."; \
		exit 1; \
	fi

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(call docker_push,$(BUNDLE_IMG))

CATALOG_DIR := $(LOCAL)/catalog
CATALOG_TEMPLATE ?= $(CATALOG_DIR)/basic.yaml
EMPTY_CATALOG_TEMPLATE := $(LOCAL)/config/catalog/basic-template.yaml
LATEST_CATALOG_TAG = $(subst :v$(OPERATOR_VERSION),:latest,$(CATALOG_IMG))

.PHONY: extract-catalog
extract-catalog: yq
	@echo "Extracting catalog..."; \
	rm -rf catalog; \
	mkdir -p catalog; \
	container_id=$$(${CONTAINER_TOOL} create ${CATALOG_IMG}); \
	if [ -n "$$container_id" ]; then \
		$(CONTAINER_TOOL) cp $$container_id:/configs/catalog.yaml $(CATALOG_DIR)/; \
		$(CONTAINER_TOOL) rm $$container_id; \
		./scripts/convert_catalog.sh $(CATALOG_DIR)/catalog.yaml $(CATALOG_TEMPLATE); \
	else \
		echo "⚠️ Skipping extract-catalog: image $(CATALOG_IMG) not found or container could not be created."; \
	fi

# Determine the latest operator version based on the passed INPUT_CATALOG_TEMPLATE.
# If the $(INPUT_CATALOG_TEMPLATE) argument is not found or the file does not exists then it fails"; \
# make latest-version-from-catalog INPUT_CATALOG_TEMPLATE=catalog/catalog-template.yaml
.PHONY: latest-version-from-catalog
latest-version-from-catalog: yq
	@if [ -z "$(INPUT_CATALOG_TEMPLATE)" ]; then \
		echo "ERROR: INPUT_CATALOG_TEMPLATE argument is required (e.g. make latest-version-from-catalog INPUT_CATALOG_TEMPLATE=catalog/basic.yaml)"; \
		exit 1; \
	elif [ ! -f "$(INPUT_CATALOG_TEMPLATE)" ]; then \
		echo "ERROR: File not found: $(INPUT_CATALOG_TEMPLATE)"; \
		exit 1; \
	else \
		operator_version=$$($(YQ) e ".entries[] | select(.schema == \"olm.channel\" and .name == \"$(FAST_CHANNEL)\") | .entries[].name" $(INPUT_CATALOG_TEMPLATE) | sed 's/.*\.v//' | sort -V | tail -n 1); \
		echo "OPERATOR_VERSION=$$operator_version"; \
	fi; \

# Converts an existing SQLite-based catalog to a file-based catalog (FBC).
# If SQLite catalog database file 'database/index.db' exists, it will be used or index image is pulled for catalog index.
.PHONY: convert-fbc
convert-fbc: opm yq
	rm -rf catalog.Dockerfile catalog
	mkdir -p catalog

	$(OPM) index add --container-tool $(CONTAINER_TOOL) --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)
	@if [ -f database/index.db ]; then \
		echo "Base catalog '$(CATALOG_BASE_IMG)' found. Migrating to $(CATALOG_DIR)..."; \
		$(OPM) migrate database/index.db $(CATALOG_DIR) -o yaml; \
	else \
		echo "ℹ️  Loading catalog index from '$(CATALOG_IMG)'..."; \
		$(OPM) migrate $(CATALOG_IMG) $(CATALOG_DIR) -o yaml; \
	fi

	$(OPM) validate $(CATALOG_DIR)
	$(OPM) alpha convert-template basic -o yaml $(CATALOG_DIR)/zyron-containersecurity/catalog.yaml > $(CATALOG_TEMPLATE)
	$(YQ) -i e 'select(.schema == "olm.template.basic").entries[] |= select(.schema == "olm.channel" and .name == "$(FAST_CHANNEL)").entries += [{"name" : "zyron-containersecurity.v$(OPERATOR_VERSION)", "replaces": "zyron-containersecurity.v$(PREVIOUS_OPERATOR_VERSION)"}]' $(CATALOG_TEMPLATE)
	$(YQ) -i e 'select(.schema == "olm.template.basic").entries += [{"schema" : "olm.bundle", "image": "$(BUNDLE_IMAGE)"}]' $(CATALOG_TEMPLATE)

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-generate
catalog-generate: opm yq
	@if [ "$(CATALOG_MODE)" = "fbc" ]; then \
		echo "Building catalog in FBC mode..."; \
		rm -rf catalog.Dockerfile $(CATALOG_DIR)/catalog.yaml; \
		mkdir -p $(CATALOG_DIR); \
		\
		if [ ! -f "$(CATALOG_TEMPLATE)" ]; then \
			echo "$(CATALOG_TEMPLATE) not found. Creating from $(EMPTY_CATALOG_TEMPLATE) ..."; \
			cp $(EMPTY_CATALOG_TEMPLATE) $(CATALOG_TEMPLATE); \
		fi; \
		\
		./scripts/update-catalog.sh $(CATALOG_TEMPLATE) $(BUNDLE_IMGS) $(FAST_CHANNEL); \
		$(OPM) alpha render-template basic --migrate-level=bundle-object-to-csv-metadata -o yaml < $(CATALOG_TEMPLATE) > $(CATALOG_DIR)/catalog.yaml; \
		\
		if [ ! -f "$(CATALOG_DIR)/catalog.yaml" ] || [ ! -s "$(CATALOG_DIR)/catalog.yaml" ]; then \
			echo "Error: Catalog '$(CATALOG_DIR)/catalog.yaml' is empty."; \
			exit 1; \
		fi; \
		$(OPM) validate $(CATALOG_DIR); \
		$(OPM) generate dockerfile $(CATALOG_DIR); \
	elif [ "$(CATALOG_MODE)" = "sqlite" ]; then \
		echo "Building catalog in SQLite mode..."; \
		$(OPM) index add --container-tool $(CONTAINER_TOOL) --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT) --generate --out-dockerfile catalog.Dockerfile; \
	else \
		echo "Error: Unsupported catalog mode: $(CATALOG_MODE). Set CATALOG_MODE to 'fbc' or 'sqlite'."; \
		exit 1; \
	fi

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:v${OPERATOR_VERSION}

ifeq ($(CATALOG_MODE), sqlite)
ifneq ($(origin PREVIOUS_OPERATOR_VERSION), undefined)
CATALOG_BASE_IMG ?= $(IMAGE_TAG_BASE)-catalog:v${PREVIOUS_OPERATOR_VERSION}
endif

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := $$($(CONTAINER_TOOL) manifest inspect $(CATALOG_BASE_IMG) > /dev/null 2>&1 && echo "--from-index $(CATALOG_BASE_IMG)" || echo "")
endif
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: catalog-generate ## Build a catalog image.
	$(CONTAINER_TOOL) build --no-cache -f catalog.Dockerfile -t $(CATALOG_IMG) $(if $(filter true,$(ADD_LATEST_TAG)),-t $(LATEST_CATALOG_TAG),) .

.PHONY: catalog-buildx
catalog-buildx: catalog-generate
	echo "Building catalog using $(CONTAINER_TOOL) container tool..."
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' catalog.Dockerfile > Dockerfile.cross
	@if [ "$(CONTAINER_TOOL)" = "docker" ]; then \
		docker buildx create --name operator-catalog-builder --driver docker-container --use; \
		docker buildx build --no-cache --platform=$(PLATFORMS) -t $(CATALOG_IMG) $(if $(filter true,$(ADD_LATEST_TAG)),-t $(LATEST_CATALOG_TAG),) -f Dockerfile.cross --push .; \
		docker buildx rm operator-catalog-builder; \
	elif [ "$(CONTAINER_TOOL)" = "podman" ]; then \
		podman manifest rm $(CATALOG_IMG) || true; \
		podman build --platform $(PLATFORMS) --manifest $(CATALOG_IMG) -t $(CATALOG_IMG) $(if $(filter true,$(ADD_LATEST_TAG)),-t $(LATEST_CATALOG_TAG),) -f Dockerfile.cross .; \
		podman manifest push --all $(CATALOG_IMG) docker://$(CATALOG_IMG); \
	else \
		echo "Error: Unsupported container tool: $(CONTAINER_TOOL)."; \
		exit 1; \
	fi
	rm Dockerfile.cross

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(call docker_push,$(CATALOG_IMG))

POLICY_JSON := '{"default":[{"type":"insecureAcceptAnything"}]}'

.PHONY: add-container-policy
add-container-policy:
	@if [ ! -f ~/.config/containers/policy.json ]; then \
		mkdir -p ~/.config/containers; \
		pwd ~/.config/containers/policy.json; \
		printf $(POLICY_JSON) > ~/.config/containers/policy.json; \
		echo "Added container policy configuration"; \
	else \
		echo "Container policy configuration already exists."; \
	fi; \

# --- Variables ---
HELM_CHART_VERSION  ?= 
HELM_CHARTS_DIR     ?= helm-charts
HELM_ZCS_CHART_DIR ?= emprovise-container-security

# --- Targets ---

.PHONY: load-helm-chart
load-helm-chart: | $(HELM_CHARTS_DIR) yq
	@echo "☸️  Removing existing $(HELM_ZCS_CHART_DIR) Helm Chart" >&2; \
	rm -rf $(HELM_CHARTS_DIR)/$(HELM_ZCS_CHART_DIR); \
	TEMP_TAR=$$(mktemp); \
	\
	if [ -n "$(HELM_CHART_VERSION)" ]; then \
		echo "☸️  Loading helm chart version $(HELM_CHART_VERSION)" >&2; \
		echo "⬇️  Downloading Helm chart tarball..." >&2; \
		curl -fLsS "https://github.com/emprovise/zyron-container-security-helm/archive/refs/tags/$$HELM_CHART_VERSION.tar.gz" -o "$$TEMP_TAR"; \
	else \
		echo "☸️  Loading latest helm chart version" >&2; \
		echo "⬇️  Downloading Helm chart tarball..." >&2; \
		curl -fLsS "https://github.com/emprovise/zyron-container-security-helm/archive/main.tar.gz" -o "$$TEMP_TAR"; \
		HELM_CHART_VERSION="main"; \
	fi; \
	\
	if [ ! -s "$$TEMP_TAR" ]; then \
		echo "❌ Downloaded file is empty or not found. Exiting." >&2; \
		rm -f "$$TEMP_TAR"; \
		exit 1; \
	fi; \
	tar xzf "$$TEMP_TAR" -C $(HELM_CHARTS_DIR)/; \
	rm -f "$$TEMP_TAR"; \
	mv "$(HELM_CHARTS_DIR)/zyron-container-security-helm-$$HELM_CHART_VERSION" "$(HELM_CHARTS_DIR)/$(HELM_ZCS_CHART_DIR)"; \
	echo "☸️  Download complete." >&2; \

	@if [ -z "$(HELM_CHART_VERSION)" ]; then \
		HELM_CHART_VERSION=$$($(YQ) -r '.version' "$(HELM_CHARTS_DIR)/$(HELM_ZCS_CHART_DIR)/Chart.yaml"); \
	fi; \
	echo "HELM_CHART_VERSION=$$HELM_CHART_VERSION"; \

$(HELM_CHARTS_DIR):
	mkdir -p $(HELM_CHARTS_DIR)

# --- SUBST ---

YAML_FILES := $(shell find config -type f \( -name "*.yaml" -o -name "*.yml" \))

SAMPLE_YAML := config/samples/zyron-containersecurity-sample.yaml
.PHONY: subst
subst: yq
	@for file in $(YAML_FILES); do \
		if grep -qE '\$${ZCS_OPERATOR_BASE_IMG_URL}|\$${OPERATOR_VERSION}' "$$file"; then \
			backup="$$file.bak"; \
			echo "Backing up $$file to $$backup"; \
			cp "$$file" "$$backup"; \
			envsubst '$${ZCS_OPERATOR_BASE_IMG_URL} $${OPERATOR_VERSION}' < "$$file" > "$$file.tmp" && mv "$$file.tmp" "$$file"; \
			echo "Processed $$file"; \
		fi \
	done
	cp $(SAMPLE_YAML) $(SAMPLE_YAML).bak
	@if [ -n "$(V1_ENDPOINT)" ]; then \
		$(YQ) -i e '.spec.zyron.endpoint = strenv(V1_ENDPOINT)' $(SAMPLE_YAML); \
	fi
	$(YQ) -i e '.spec.zyron.bootstrapToken = strenv(BOOTSTRAP_TOKEN)' $(SAMPLE_YAML)

.PHONY: clean
clean:
	@echo "Restoring backup files..."
	@find config -type f -name "*.bak" | while read bakfile; do \
		origfile=$$(echo $$bakfile | sed 's/\.bak$$//'); \
		echo "Restoring $$bakfile to $$origfile"; \
		mv -f "$$bakfile" "$$origfile"; \
	done

	rm -rf bundle database artifacts bundle.Dockerfile catalog.Dockerfile Dockerfile.cross

ifneq ($(ignore),catalog)
	rm -rf catalog
endif

# --- OPM INSTALL ---

# OPM_VERSION ?= v1.32.0
OPM_VERSION ?= v1.57.0
OPM ?= $(LOCAL_BIN)/opm

.PHONY: opm
opm:
	@if [ -x $(OPM) ]; then \
		echo "opm already installed at $(OPM)"; \
	else \
		echo "Downloading opm $(OPM_VERSION) for $(OS)/$(ARCH)..."; \
		set -e; \
		mkdir -p $(dir $(OPM)) ;\
		curl -Lo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/$(OPM_VERSION)/$(OS)-$(ARCH)-opm; \
		chmod +x $(OPM); \
		echo "opm installed at $(OPM)"; \
		$(OPM) version; \
	fi

.PHONY: kustomize-install
kustomize-install:
	@echo "Installing kustomize $(KUSTOMIZE_VERSION) for $(OS)/$(ARCH)..."
	curl -sL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/$(KUSTOMIZE_VERSION)/kustomize_$(KUSTOMIZE_VERSION)_$(OS)_$(ARCH).tar.gz -o kustomize.tar.gz
	tar -xzf kustomize.tar.gz
	chmod +x kustomize
	sudo mv kustomize $(BIN_DIR)/
	rm -f kustomize.tar.gz
	@echo "✅ kustomize installed at $(BIN_DIR)/kustomize"
	@kustomize version

.PHONY: set-openshift-annotations
set-openshift-annotations:
	@echo "Setting OpenShift version annotations in bundle/metadata/annotations.yaml and bundle.Dockerfile"
	@echo "" >> bundle/metadata/annotations.yaml
	@echo "  # Set minimum OpenShift version" >> bundle/metadata/annotations.yaml
	@echo "  com.redhat.openshift.versions: $(SUPPORTED_OPENSHIFT_VERSIONS)" >> bundle/metadata/annotations.yaml
	@echo "\n# Set minimum OpenShift version" >> bundle.Dockerfile
	@echo "LABEL com.redhat.openshift.versions=$(SUPPORTED_OPENSHIFT_VERSIONS)" >> bundle.Dockerfile
	@echo "LABEL com.redhat.delivery.operator.bundle=true" >> bundle.Dockerfile
	@echo "\nUSER 1001" >> bundle.Dockerfile	

PREFLIGHT = $(LOCAL_BIN)/preflight
PREFLIGHT_VERSION ?= 1.14.0

.PHONY: preflight
preflight: ## Download preflight locally if necessary.
	@{ \
	set -e ;\
	mkdir -p $(dir $(PREFLIGHT)) ;\
	OS=$$(uname | tr '[:upper:]' '[:lower:]') ;\
	ARCH=$$(uname -m) ;\
	if [ "$$ARCH" = "x86_64" ]; then ARCH="amd64"; fi ;\
	if [ "$$ARCH" = "aarch64" ]; then ARCH="arm64"; fi ;\
	curl -sSLo $(PREFLIGHT) https://github.com/redhat-openshift-ecosystem/openshift-preflight/releases/download/$(PREFLIGHT_VERSION)/preflight-$$OS-$$ARCH ;\
	chmod +x $(PREFLIGHT) ;\
	$(PREFLIGHT) --version ;\
	}

YQ_VERSION ?= v4.45.1

.PHONY: yq
YQ = $(LOCAL_BIN)/yq
yq:
	@if [ ! -d ${LOCAL_BIN} ]; then mkdir -p ${LOCAL_BIN}; fi
	@curl -sLO https://github.com/mikefarah/yq/releases/download/$(YQ_VERSION)/yq_$(OS)_$(ARCH) && mv yq_$(OS)_$(ARCH) $(YQ) && chmod +x $(YQ)

# --- End of Makefile ---