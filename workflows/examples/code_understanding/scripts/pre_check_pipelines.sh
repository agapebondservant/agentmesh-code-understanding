#!/usr/bin/env bash
# Exits 0 (skip) if pipelines are already uploaded to KFP, 1 (proceed) otherwise.

python3 - <<'PYEOF'
import os, sys, json, ssl, urllib3
ssl._create_default_https_context = ssl._create_unverified_context
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
from kfp.client import Client

client = Client(host=os.environ["KFP_HOST"])
result = client.list_pipelines(filter=json.dumps({
    "predicates": [{"key": "display_name", "op": "EQUALS", "string_value": "single-data-generation-pipeline"}]
}))
if result.pipelines:
    print("Pipelines already uploaded, skipping.")
    sys.exit(0)
sys.exit(1)
PYEOF
