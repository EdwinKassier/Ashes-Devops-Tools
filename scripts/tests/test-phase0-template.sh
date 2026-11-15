#!/usr/bin/env bash
# templates/aws/bootstrap/phase0-management.yaml:
#   - the management plan role (tfc-mgmt-plan) carries the same data-read deny
#     as the member-account tfc-plan role (modules/aws/iam/tfc-oidc-baseline:
#     plan_role_data_read_deny_actions and the API key paths), as exact sets;
#   - aws-security and aws-backup are not trusted by the admin role by default;
#   - both roles deny editing the phase-0 roles and break-glass, and assuming
#     OrganizationAccountAccessRole (same actions as tfc-management-roles).
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

# SEC-4: both phase-0 roles carry an inline self-protection deny that mirrors
# DenyManagementRoleTampering / DenyMemberAccountPivot in
# modules/aws/iam/tfc-management-roles/main.tf. The protected roles are named
# exactly: aws-organization itself manages the tfc-mgmt-<workspace>-* roles.
mgmt = (root / "modules/aws/iam/tfc-management-roles/main.tf").read_text()
tamper_block = re.search(r'Sid    = "DenyManagementRoleTampering".*?Action = \[(.*?)\]', mgmt, re.S)
pivot_block = re.search(r'Sid      = "DenyMemberAccountPivot".*?Action   = \[(.*?)\]', mgmt, re.S)
if tamper_block is None or pivot_block is None:
    sys.exit("  FAIL cannot find DenyManagementRoleTampering / DenyMemberAccountPivot in tfc-management-roles")
tamper_actions = set(re.findall(r'"(iam:[A-Za-z]+)"', tamper_block.group(1)))
pivot_actions = set(re.findall(r'"(sts:[A-Za-z]+)"', pivot_block.group(1)))
if len(tamper_actions) < 8 or len(pivot_actions) < 1:
    sys.exit("  FAIL parsed too few actions from tfc-management-roles; the parser is out of date")
want_roles = {
    "arn:${AWS::Partition}:iam::${AWS::AccountId}:role/tfc-mgmt-plan",
    "arn:${AWS::Partition}:iam::${AWS::AccountId}:role/tfc-mgmt-apply",
    "arn:${AWS::Partition}:iam::${AWS::AccountId}:role/OrganizationBreakGlass",
}
want_pivot = {"arn:${AWS::Partition}:iam::*:role/OrganizationAccountAccessRole"}


def subs(resource):
    items = resource if isinstance(resource, list) else [resource]
    return {r.get("Fn::Sub", f"<bad: {r}>") if isinstance(r, dict) else f"<bad: {r}>" for r in items}


for role in ("TfcMgmtApplyRole", "TfcMgmtPlanRole"):
    props = tpl["Resources"][role]["Properties"]
    pols = {p["PolicyName"]: p["PolicyDocument"] for p in props.get("Policies", [])}
    doc = pols.get("deny-self-tampering")
    if doc is None:
        fail.append(f"{role} needs an inline deny-self-tampering policy")
        continue
    stmts = {s.get("Sid"): s for s in doc["Statement"]}
    t = stmts.get("DenyManagementRoleTampering")
    if t is None or t["Effect"] != "Deny":
        fail.append(f"{role}: deny-self-tampering needs a DenyManagementRoleTampering Deny statement")
    else:
        if set(t["Action"]) != tamper_actions:
            fail.append(
                f"{role}: DenyManagementRoleTampering actions differ from tfc-management-roles: "
                f"missing {sorted(tamper_actions - set(t['Action']))}, extra {sorted(set(t['Action']) - tamper_actions)}"
            )
        if subs(t["Resource"]) != want_roles:
            fail.append(f"{role}: DenyManagementRoleTampering must cover exactly {sorted(want_roles)}, got {sorted(subs(t['Resource']))}")
    pv = stmts.get("DenyMemberAccountPivot")
    if pv is None or pv["Effect"] != "Deny":
        fail.append(f"{role}: deny-self-tampering needs a DenyMemberAccountPivot Deny statement")
    else:
        if set(pv["Action"]) != pivot_actions:
            fail.append(f"{role}: DenyMemberAccountPivot actions differ from tfc-management-roles: {sorted(pv['Action'])} vs {sorted(pivot_actions)}")
        if subs(pv["Resource"]) != want_pivot:
            fail.append(f"{role}: DenyMemberAccountPivot must cover {sorted(want_pivot)}, got {sorted(subs(pv['Resource']))}")

if fail:
    print("\n".join("  FAIL " + f for f in fail), file=sys.stderr)
    sys.exit(1)
print(f"phase0 template: ok ({len(module_actions)} deny actions and {len(module_paths)} API key paths in step with tfc-oidc-baseline; self-protection in step with tfc-management-roles)")
PY
