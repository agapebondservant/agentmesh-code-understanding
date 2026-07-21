ENV_FILE     ?= .env
GIT_REPO_URL := $(shell git remote get-url origin 2>/dev/null | sed 's|^git@\([^:]*\):\(.*\)$$|https://\1/\2|')

install:
	set -a && . $(ENV_FILE) && set +a && \
	helm template resources/helm -s templates/namespace.yaml --set namespace="$$KFP_NAMESPACE" | oc apply -f -
	oc delete secret code-understanding-env --ignore-not-found=true
	oc create secret generic code-understanding-env --from-env-file $(ENV_FILE) || \
		(echo "ERROR: .env file not found ($(ENV_FILE))"; exit 1)
	set -a && . $(ENV_FILE) && set +a && \
	oc patch secret code-understanding-env -n $$KFP_NAMESPACE \
		--type=merge \
		-p "{\"stringData\":{\"MLFLOW_NAMESPACE\":\"$$KFP_NAMESPACE\",\"MLFLOW_TRACKING_TOKEN\":\"$$(oc whoami --show-token)\"}}" && \
	oc create secret generic git-credentials \
		--from-literal=GIT_USERNAME="$$GIT_USERNAME" \
		--from-literal=GIT_TOKEN="$$GIT_TOKEN" \
		-n $$KFP_NAMESPACE --dry-run=client -o yaml | oc apply -f - && \
	oc adm policy add-role-to-user edit -z default -n $$KFP_NAMESPACE && \
	helm upgrade --install agent-mesh-for-sw resources/helm \
		--create-namespace \
		--set namespace="$$KFP_NAMESPACE" \
		--set repoUrl="$(GIT_REPO_URL)" \
		--set minio.rootUser="$$AWS_ACCESS_KEY_ID" \
		--set minio.rootPassword="$$AWS_SECRET_ACCESS_KEY" \
		--set dataGeneration.image.registry="$$KFP_IMAGE_REGISTRY" \
		--set dataGeneration.image.name="$$KFP_DATA_GENERATION_BASE_IMAGE_NAME" \
		--set dataGeneration.image.version="$$KFP_DATA_GENERATION_BASE_IMAGE_VERSION" \
		--set graphrag.image.registry="$$KFP_IMAGE_REGISTRY" \
		--set graphrag.image.name="$$KFP_INDEXING_BASE_IMAGE_NAME" \
		--set graphrag.image.version="$$KFP_INDEXING_BASE_IMAGE_VERSION" \
		--set analysis.image.registry="$$KFP_IMAGE_REGISTRY" \
		--set analysis.image.name="$$KFP_ANALYSIS_BASE_IMAGE_NAME" \
		--set analysis.image.version="$$KFP_ANALYSIS_BASE_IMAGE_VERSION"
	set -a && . $(ENV_FILE) && set +a && \
	[ "$$ASSET_LOADER" = "mlflow" ] && $(MAKE) preload-mlflow-assets || true

build-images:
	set -a && . $(ENV_FILE) && set +a && \
	DATAGEN_IMG="$$KFP_IMAGE_REGISTRY/$$KFP_DATA_GENERATION_BASE_IMAGE_NAME:$$KFP_DATA_GENERATION_BASE_IMAGE_VERSION" && \
	INDEX_IMG="$$KFP_IMAGE_REGISTRY/$$KFP_INDEXING_BASE_IMAGE_NAME:$$KFP_INDEXING_BASE_IMAGE_VERSION" && \
	ANALYSIS_IMG="$$KFP_IMAGE_REGISTRY/$$KFP_ANALYSIS_BASE_IMAGE_NAME:$$KFP_ANALYSIS_BASE_IMAGE_VERSION" && \
	podman build -t "$$DATAGEN_IMG" resources/images/data-generation && \
	podman push "$$DATAGEN_IMG" && \
	podman build -t "$$INDEX_IMG" resources/images/data-indexing && \
	podman push "$$INDEX_IMG" && \
	podman build -t "$$ANALYSIS_IMG" resources/images/data-generation && \
	podman push "$$ANALYSIS_IMG"

preload-mlflow-assets:
	set -a && . $(ENV_FILE) && set +a && \
	oc delete job upload-assets -n $$KFP_NAMESPACE --ignore-not-found=true && \
	oc apply -f resources/helm/templates/upload-assets-job.yaml

run-pipelines:
	set -a && . $(ENV_FILE) && set +a && \
	workflows/examples/code_understanding/run_pipelines.sh $(ARGS)
