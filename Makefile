ENV_FILE ?= .env
GIT_REPO_URL := $(shell git remote get-url origin 2>/dev/null | sed 's|^git@\([^:]*\):\(.*\)$$|https://\1/\2|')

install:
	oc create secret generic code-understanding-env --from-env-file $(ENV_FILE) || \
		(echo "ERROR: .env file not found ($(ENV_FILE))"; exit 1)
	set -a && . $(ENV_FILE) && set +a && \
    oc create secret generic git-credentials \
    --from-literal=GIT_USERNAME='$(GIT_USERNAME)' \
    --from-literal=GIT_TOKEN='$(GIT_TOKEN)' \
    -n $(KFP_NAMESPACE) --dry-run=client -o yaml | oc apply -f - && \
	helm upgrade --install agent-mesh-for-sw resources/helm \
		--create-namespace \
		--set namespace="$$KFP_NAMESPACE" \
		--set repoUrl="$(GIT_REPO_URL)" \
		--set minio.rootUser="$$AWS_ACCESS_KEY_ID" \
		--set minio.rootPassword="$$AWS_SECRET_ACCESS_KEY"

run-pipelines:
	set -a && . $(ENV_FILE) && set +a && \
	workflows/examples/code_understanding/run_pipelines.sh $(ARGS)
