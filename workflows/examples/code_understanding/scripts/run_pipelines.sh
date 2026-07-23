#!/usr/bin/env bash
# Converts kubeflow_generation.ipynb to a script, compiles all KFP pipelines,
# and submits or uploads the requested ones to Kubeflow Pipelines.
#
# Usage:
#   ./run_pipelines.sh --single          # run single-repo pipeline (data generation → indexing → analysis)
#   ./run_pipelines.sh --aggregated      # run aggregated data generation pipeline
#   ./run_pipelines.sh --upload-single   # upload single-repo pipeline template to KFP (no run)
#   ./run_pipelines.sh --upload-aggregated  # upload aggregated pipeline template to KFP (no run)
#
# Environment variables:
#   KFP_NAMESPACE         Kubernetes namespace (KFP_HOST is derived from this)
#   KFP_IMAGE_REGISTRY    Image registry that hosts pipeline images (example: quay.io)
#   TARGET_PATH           Output path from data generation, used as codebase input for indexing (default: target)
#   GRAPHRAG_SOURCE_PATH  GraphRAG source path for indexing and analysis (default: graph_rag_app/source)

set -euo pipefail

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [OPTION]...

Options:
  --single            Run single-repo pipeline (data generation -> indexing -> analysis)
  --aggregated        Run aggregated data generation pipeline
  --upload-single     Upload single-repo pipeline template to KFP (no run)
  --upload-aggregated Upload aggregated pipeline template to KFP (no run)
  -h, --help          Show this help message

Environment variables:
  KFP_NAMESPACE         Kubernetes namespace, used to derive KFP_HOST (required)
  KFP_IMAGE_REGISTRY    Image registry that hosts pipeline images (required)
  KFP_DATA_GENERATION_OUTPUT_PATH  Output path from data generation (default: target)
  KFP_DATA_INDEXING_OUTPUT_PATH    GraphRAG source path for indexing and analysis (default: graph_rag_app/source)
EOF
}

if [[ -z "${KFP_NAMESPACE:-}" ]]; then
    echo "Error: KFP_NAMESPACE must be set and non-empty." >&2
    exit 1
fi

KFP_HOST="${KFP_HOST:-https://ds-pipeline-dspa.${KFP_NAMESPACE}.svc.cluster.local:8443}"
if [[ -z "${KFP_IMAGE_REGISTRY}" ]]; then
    echo "Error: KFP_IMAGE_REGISTRY must be set and non-empty." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_UNDERSTANDING_DIR="$(dirname "$SCRIPT_DIR")"
COMPILED_DIR="$SCRIPT_DIR/compiled_pipelines"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TARGET_PATH="${KFP_DATA_GENERATION_OUTPUT_PATH:-target}"
GRAPHRAG_SOURCE_PATH="${KFP_DATA_INDEXING_OUTPUT_PATH:-graph_rag_app/source}"

TEMP_SCRIPT="$COMPILED_DIR/${TIMESTAMP}_kubeflow_generation.py"
YAML_DIR="$COMPILED_DIR/${TIMESTAMP}_yamls"

mkdir -p "$COMPILED_DIR"

# ---------------------------------------------------------------------------
# Convert kubeflow_generation.ipynb to a flat Python script, then compile
# all pipelines to YAML in one pass.
# ---------------------------------------------------------------------------
echo "Converting kubeflow_generation.ipynb to script..."
jupyter nbconvert --to script "$CODE_UNDERSTANDING_DIR/utils/notebooks/kubeflow_generation.ipynb" \
    --output "$COMPILED_DIR/${TIMESTAMP}_kubeflow_generation"

echo "Compiling all pipelines..."
PIPELINE_COMPILE_ONLY=1 \
KFP_PIPELINE_OUTPUT_DIR="$YAML_DIR" \
python3 "$TEMP_SCRIPT"
echo "  Compiled YAMLs -> $YAML_DIR/"

rm -f "$TEMP_SCRIPT"

# ---------------------------------------------------------------------------
# submit_pipeline
#   Submits a compiled YAML to Kubeflow Pipelines.
#
#   $1  yaml      path to the compiled pipeline YAML
#   $2  run_name  name for the KFP run
#   $3  params    optional JSON string of run parameters (default: {})
# ---------------------------------------------------------------------------
submit_pipeline() {
    local yaml="$1"
    local run_name="$2"
    local params="${3:-{}}"
    echo "Submitting $run_name to $KFP_HOST..."
    python3 - "$yaml" "$run_name" "$params" <<PYEOF
import sys, json, kfp
client = kfp.Client(host="$KFP_HOST", namespace="$KFP_NAMESPACE",
                    ssl_ca_cert="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
run = client.create_run_from_pipeline_package(
    pipeline_file=sys.argv[1],
    run_name=sys.argv[2],
    params=json.loads(sys.argv[3]),
    enable_caching=False,
)
print(f"  Submitted run id: {run.run_id}")
PYEOF
    echo "  OK: $run_name submitted."
}

# ---------------------------------------------------------------------------
# upload_pipeline
#   Uploads a compiled YAML to Kubeflow Pipelines as a reusable template
#   without creating a run.
#
#   $1  yaml           path to the compiled pipeline YAML
#   $2  pipeline_name  name to register the pipeline under in KFP
# ---------------------------------------------------------------------------
upload_pipeline() {
    local yaml="$1"
    local pipeline_name="$2"
    echo "Uploading $pipeline_name to $KFP_HOST..."
    python3 - "$yaml" "$pipeline_name" <<PYEOF
import sys, kfp
client = kfp.Client(host="$KFP_HOST", namespace="$KFP_NAMESPACE",
                    ssl_ca_cert="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt")
pipeline = client.upload_pipeline(
    pipeline_package_path=sys.argv[1],
    pipeline_name=sys.argv[2],
)
print(f"  Uploaded pipeline id: {pipeline.pipeline_id}")
PYEOF
    echo "  OK: $pipeline_name uploaded."
}

RUN_SINGLE=false
RUN_AGGREGATED=false
UPLOAD_SINGLE=false
UPLOAD_AGGREGATED=false

if [[ $# -eq 0 ]]; then
    RUN_SINGLE=true
    RUN_AGGREGATED=true
fi

for arg in "$@"; do
    case "$arg" in
        --single)            RUN_SINGLE=true ;;
        --aggregated)        RUN_AGGREGATED=true ;;
        --upload-single)     UPLOAD_SINGLE=true ;;
        --upload-aggregated) UPLOAD_AGGREGATED=true ;;
        -h|--help)           usage; exit 0 ;;
        *) echo "Error: Unknown argument: $arg" >&2; usage; exit 1 ;;
    esac
done

if $RUN_SINGLE; then
    submit_pipeline "$YAML_DIR/single_full.yaml" "single_full_${TIMESTAMP}" \
        "{\"target_path\": \"$TARGET_PATH\", \"graphrag_source_path\": \"$GRAPHRAG_SOURCE_PATH\"}"
fi

$RUN_AGGREGATED && submit_pipeline "$YAML_DIR/aggregated.yaml" "aggregated_${TIMESTAMP}"

$UPLOAD_SINGLE     && upload_pipeline "$YAML_DIR/single_full.yaml" "single_full"
$UPLOAD_AGGREGATED && upload_pipeline "$YAML_DIR/aggregated.yaml"  "aggregated"

echo "All done."
