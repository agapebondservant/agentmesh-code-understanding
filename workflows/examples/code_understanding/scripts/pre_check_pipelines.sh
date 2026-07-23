#!/usr/bin/env bash
# Exits 0 (skip) if pipelines are already uploaded to KFP, 1 (proceed) otherwise.

python3 - <<'PYEOF'
import os, sys, json, urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
import kfp_server_api.configuration as _kfp_conf
_orig_init = _kfp_conf.Configuration.__init__
def _no_verify_init(self, *args, **kwargs):
    _orig_init(self, *args, **kwargs)
    self.verify_ssl = False
_kfp_conf.Configuration.__init__ = _no_verify_init
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
