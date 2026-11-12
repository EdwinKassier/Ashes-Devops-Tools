#!/usr/bin/env bash
# templates/aws/bootstrap/phase0-management.yaml:
#   - the management plan role (tfc-mgmt-plan) carries the same data-read deny
#     as the member-account tfc-plan role (modules/aws/iam/tfc-oidc-baseline:
#     plan_role_data_read_deny_actions and the API key paths), as exact sets;
#   - aws-security and aws-backup are not trusted by the admin role by default.
#   bash scripts/tests/test-phase0-template.sh   (make test-scripts; needs PyYAML,
#   which the yamllint requirements install in CI)
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

python3 - "${REPO_ROOT}" <<'PY'
import pathlib
import re
import sys

import yaml

root = pathlib.Path(sys.argv[1])
tpl = yaml.safe_load((root / "templates/aws/bootstrap/phase0-management.yaml").read_text())
src = (root / "modules/aws/iam/tfc-oidc-baseline/main.tf").read_text()

block = re.search(r"plan_role_data_read_deny_actions = \[(.*?)\n  \]", src, re.S)
paths = re.search(r'plan_role_api_key_read_deny_statement = \{.*?for r in \[([^\]]*)\]', src, re.S)
if block is None or paths is None:
    sys.exit("  FAIL cannot find the plan-role deny lists in modules/aws/iam/tfc-oidc-baseline/main.tf")
module_actions = set(re.findall(r'"([a-z0-9-]+:[A-Za-z0-9*]+)"', block.group(1)))
module_paths = set(re.findall(r'"(/[^"]+)"', paths.group(1)))
if len(module_actions) < 10 or len(module_paths) < 1:
    sys.exit("  FAIL parsed too few deny entries from tfc-oidc-baseline; the parser is out of date")

fail = []
if tpl["Parameters"]["TrustSecurityAndBackup"]["Default"] != "false":
    fail.append('TrustSecurityAndBackup must default to "false"')

plan = tpl["Resources"]["TfcMgmtPlanRole"]["Properties"]
pols = {p["PolicyName"]: p["PolicyDocument"] for p in plan.get("Policies", [])}
deny = pols.get("data-read-deny")
if deny is None:
    fail.append("TfcMgmtPlanRole needs an inline data-read-deny policy")
else:
    stmts = {s.get("Sid"): s for s in deny["Statement"]}
    data = stmts.get("DenyDataPlaneReads")
    if data is None or data["Effect"] != "Deny" or data.get("Resource") != "*":
        fail.append("data-read-deny needs a DenyDataPlaneReads statement on Resource \"*\"")
    else:
        actions = set(data["Action"] if isinstance(data["Action"], list) else [data["Action"]])
        if actions != module_actions:
            fail.append(
                "DenyDataPlaneReads differs from plan_role_data_read_deny_actions: "
                f"missing {sorted(module_actions - actions)}, extra {sorted(actions - module_actions)}"
            )
    api = stmts.get("DenyApiKeyValueReads")
    if api is None or api["Effect"] != "Deny" or api["Action"] != "apigateway:GET":
        fail.append("data-read-deny needs a DenyApiKeyValueReads statement (Deny apigateway:GET)")
    else:
        prefix = "arn:${AWS::Partition}:apigateway:*::"
        got = set()
        for r in api["Resource"]:
            sub = r.get("Fn::Sub", "") if isinstance(r, dict) else ""
            got.add(sub[len(prefix):] if sub.startswith(prefix) else f"<bad: {r}>")
        if got != module_paths:
            fail.append(
                "DenyApiKeyValueReads paths differ from tfc-oidc-baseline: "
                f"missing {sorted(module_paths - got)}, extra {sorted(got - module_paths)}"
            )

if fail:
    print("\n".join("  FAIL " + f for f in fail), file=sys.stderr)
    sys.exit(1)
print(f"phase0 template: ok ({len(module_actions)} deny actions and {len(module_paths)} API key paths in step with tfc-oidc-baseline)")
PY
