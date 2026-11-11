#!/usr/bin/env python3
"""Pre-plan gate: no plan/apply-time code execution, no credential redirection.

A plan runs with the workspace's credentials and environment variables
(TFE_TOKEN, SUPABASE_ACCESS_TOKEN, the cloud plan identity). HCP Terraform
evaluates policies/opa/no_plan_time_code_execution.rego only AFTER the plan,
so this check enforces the same rules on the repository source at pull-request
time. It parses every *.tf file (python-hcl2) and every *.tf.json file (json)
in the tree (it skips .git, .terraform and node_modules) and fails on:
  - a provisioner in a resource block outside the reviewed module (the module
    that the policy's allowed_provisioner_chain reaches from envs/saas) and
    outside TEST_PROVISIONER_ALLOW;
  - a provisioner in a removed block, anywhere (the plan JSON does not render
    removed blocks, so the policy cannot see these);
  - a data "external" / data "http" block, top-level or inside a check block;
  - a data "terraform_remote_state" whose backend is not a literal on the
    policy's allowed_remote_state_backends;
  - a provider that is not on the policy's allowed_provider_sources: in
    required_providers (qualified, unqualified or version-only) and as the
    provider of every provider, resource, data, ephemeral and action block;
  - a provider argument or nested block (dynamic blocks included) that matches
    the policy's endpoint_key_pattern and is not in endpoint_key_exceptions;
  - a module source that is neither local nor this repository's release tag;
  - a drift between allowed_provisioner_chain and the module calls in the code;
  - a file that does not parse (fail closed).

One source of truth: the provider, backend and endpoint lists and the
provisioner chain are READ from policies/opa/no_plan_time_code_execution*.rego
of the repository that holds this script. A fork edits only the allowlist
.rego file, and both controls follow.

Exit codes: 0 clean, 1 violations, 2 setup error (parser missing, policy
unreadable). PLAN_EXEC_ROOT overrides the tree to scan (tests).
"""
from __future__ import annotations

import json
import os
import posixpath
import re
import sys
from pathlib import Path

try:
    import hcl2
except ImportError:  # fail closed with the install hint
    sys.stderr.write(
        "check-plan-time-exec: python-hcl2 is missing. Install the pinned version:\n"
        "  python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/hcl2.txt\n"
        "(inside a virtualenv if your Python is externally managed; make install does this)\n"
    )
    sys.exit(2)

REPO = Path(__file__).resolve().parent.parent
ROOT = Path(os.environ.get("PLAN_EXEC_ROOT") or REPO).resolve()
POLICY = REPO / "policies" / "opa" / "no_plan_time_code_execution.rego"
ALLOWLIST = REPO / "policies" / "opa" / "no_plan_time_code_execution_allowlist.rego"
SKIP_DIRS = {".git", ".terraform", "node_modules"}

# The root whose module calls start the policy's allowed_provisioner_chain.
PROVISIONER_CHAIN_ROOT = "envs/saas"
# Test fixtures that never run in an HCP Terraform workspace, so the policy
# never sees them: {file: {resource address}}. tests/e2e/aws runs only through
# `terraform test` in .github/workflows/sandbox-e2e.yml (sandbox account); its
# fixed `sleep 20` waits for S3 bucket settings to become consistent.
TEST_PROVISIONER_ALLOW = {"tests/e2e/aws/main.tf": {"terraform_data.archive_settle"}}

LOCAL_MODULE = re.compile(r"^\.\.?/")
OWN_RELEASE_MODULE = re.compile(
    r"^git::https://github\.com/EdwinKassier/Ashes-Devops-Tools\.git//modules/[a-z0-9/_-]+"
    r"\?ref=v[0-9]+\.[0-9]+\.[0-9]+$"
)
DEFAULT_REGISTRY = "registry.terraform.io"
BUILTIN_TERRAFORM = "terraform.io/builtin/terraform"
TYPED_BLOCKS = ("resource", "data", "ephemeral", "action")
# python-hcl2 7.3.1 rejects a valid HCL form: a line inside parentheses that
# starts with a conditional or logical operator ("? a", ": b", "&& c").
# When the strict parse fails, the file is parsed once more with those
# newlines joined. The join only removes line breaks, so it can only hide a
# continuation line behind a comment on the line before. Such a line is part
# of an expression (never a block, key or module source), and an expression
# is never accepted where this check needs a literal.
LEADING_OPERATOR = re.compile(r"\n[ \t]*(?=(?:\?|:|&&|\|\|)\s)")


def setup_error(msg: str) -> None:
    sys.stderr.write(f"check-plan-time-exec: {msg}\n")
    sys.exit(2)


# --- read the lists from the OPA policy ------------------------------------
def _rego_rule(text: str, name: str, opener: str, closer: str, src: Path) -> str:
    """Body of a top-level `name := <opener> ... <closer>` rule, comments stripped.
    closer is a regex: the first match after the opener ends the body."""
    m = re.search(rf"^{re.escape(name)}\s*:=\s*{re.escape(opener)}(.*?){closer}",
                  text, re.M | re.S)
    if not m:
        setup_error(f"cannot read {name} from {src.relative_to(REPO)}")
    return "\n".join(line.split("#", 1)[0] for line in m.group(1).splitlines())


def rego_string_set(text: str, name: str, src: Path) -> set[str]:
    values = set(re.findall(r'"([^"]*)"', _rego_rule(text, name, "{", r"\}", src)))
    if not values:
        setup_error(f"{name} in {src.relative_to(REPO)} is empty")
    return values


def load_policy() -> dict:
    try:
        policy = POLICY.read_text(encoding="utf-8")
        allow = ALLOWLIST.read_text(encoding="utf-8")
    except OSError as exc:
        setup_error(f"cannot read the OPA policy: {exc}")
    m = re.search(r"^endpoint_key_pattern\s*:=\s*`([^`]+)`", policy, re.M)
    if not m:
        setup_error(f"cannot read endpoint_key_pattern from {POLICY.relative_to(REPO)}")
    chain = re.findall(r'\{"name":\s*"([^"]+)",\s*"source":\s*"([^"]+)"\}',
                       _rego_rule(policy, "allowed_provisioner_chain", "[", r"^\]", POLICY))
    if not chain:
        setup_error(f"allowed_provisioner_chain in {POLICY.relative_to(REPO)} is empty")
    return {
        "exec_data_types": rego_string_set(policy, "exec_data_types", POLICY),
        "endpoint_key": re.compile(m.group(1)),
        "chain": chain,
        "providers": rego_string_set(allow, "allowed_provider_sources", ALLOWLIST),
        "endpoint_exceptions": rego_string_set(allow, "endpoint_key_exceptions", ALLOWLIST),
        "backends": rego_string_set(allow, "allowed_remote_state_backends", ALLOWLIST),
    }


# --- shape helpers (HCL gives lists of one-key dicts; JSON gives dicts or lists)
def blocks(value) -> list[dict]:
    if isinstance(value, list):
        return [v for v in value if isinstance(v, dict)]
    if isinstance(value, dict):
        return [value]
    return []


def labelled(value):
    """Yield (label, body) for a one-label block map; JSON comment keys are skipped."""
    for b in blocks(value):
        for label, body in b.items():
            if label != "//":
                for one in blocks(body):
                    yield str(label), one


def typed(value):
    """Yield (type, name, body) for a two-label block map (resource, data, ...)."""
    for rtype, names in labelled(value):
        for name, body in labelled(names):
            yield rtype, name, body


def all_keys(node):
    if isinstance(node, dict):
        for k, v in node.items():
            yield str(k)
            yield from all_keys(v)
    elif isinstance(node, list):
        for v in node:
            yield from all_keys(v)


def literal(value):
    """A string that is not an expression, else None."""
    return value if isinstance(value, str) and "${" not in value else None


def normalise_source(src: str) -> str:
    parts = src.strip().lower().split("/")
    return "/".join([DEFAULT_REGISTRY] + parts) if len(parts) == 2 else "/".join(parts)


def implied_source(local: str) -> str:
    return BUILTIN_TERRAFORM if local == "terraform" else f"{DEFAULT_REGISTRY}/hashicorp/{local}"


def provider_local(rtype: str, body: dict) -> str:
    ref = body.get("provider")
    if isinstance(ref, str) and ref:
        return ref.removeprefix("${").removesuffix("}").split(".", 1)[0].strip()
    return rtype.split("_", 1)[0]


# --- checks ---------------------------------------------------------------
def required_providers(doc: dict):
    """Yield (local name, normalised source) for every required_providers entry."""
    for tf in blocks(doc.get("terraform")):
        for rp in blocks(tf.get("required_providers")):
            for name, spec in rp.items():
                if name == "//":
                    continue
                src = spec.get("source") if isinstance(spec, dict) else None
                yield str(name), normalise_source(src) if isinstance(src, str) else implied_source(str(name))


def check_doc(rel: str, doc: dict, dir_providers: dict, pol: dict, provisioner_dir: str) -> list[str]:
    out: list[str] = []

    def resolve(local: str) -> str:
        return dir_providers.get(local) or implied_source(local)

    # Provisioners.
    in_reviewed_module = posixpath.dirname(rel) == provisioner_dir
    for rtype, name, body in typed(doc.get("resource")):
        addr = f"{rtype}.{name}"
        if "provisioner" in set(all_keys(body)) and not in_reviewed_module \
                and addr not in TEST_PROVISIONER_ALLOW.get(rel, set()):
            out.append(f"{rel}: {addr} declares a provisioner (arbitrary commands at apply "
                       f"time with the workspace's credentials); only {provisioner_dir} may")
    for kind in ("removed", "import"):
        for b in blocks(doc.get(kind)):
            if "provisioner" in set(all_keys(b)):
                out.append(f"{rel}: provisioner in a {kind} block (runs at apply; the OPA "
                           "policy cannot see it)")

    # Typed blocks, including data blocks scoped inside check blocks.
    typed_blocks = [(kind, t) for kind in TYPED_BLOCKS for t in typed(doc.get(kind))]
    for _, check_body in labelled(doc.get("check")):
        typed_blocks += [("data", t) for t in typed(check_body.get("data"))]
    for kind, (rtype, name, body) in typed_blocks:
        if kind == "data" and rtype in pol["exec_data_types"]:
            out.append(f'{rel}: data "{rtype}" "{name}" runs at plan time with the '
                       "workspace's credentials and environment")
        if kind == "data" and rtype == "terraform_remote_state" \
                and literal(body.get("backend")) not in pol["backends"]:
            out.append(f"{rel}: data.terraform_remote_state.{name} backend must be a literal "
                       f"{sorted(pol['backends'])}, not {body.get('backend')!r}")
        src = resolve(provider_local(rtype, body))
        if src not in pol["providers"]:
            out.append(f'{rel}: {kind} "{rtype}" "{name}" uses provider {src}, '
                       "which is not on allowed_provider_sources")

    for local, src in required_providers(doc):
        if src not in pol["providers"]:
            out.append(f'{rel}: required_providers "{local}" = {src} is not on allowed_provider_sources')

    for pname, body in labelled(doc.get("provider")):
        src = resolve(pname)
        if src not in pol["providers"]:
            out.append(f'{rel}: provider "{pname}" ({src}) is not on allowed_provider_sources')
        for key in sorted(set(all_keys(body))):
            if pol["endpoint_key"].match(key) and key not in pol["endpoint_exceptions"]:
                out.append(f'{rel}: provider "{pname}" sets "{key}" (an endpoint, proxy or TLS '
                           "override can send the workspace's credentials to another host)")

    for mname, body in labelled(doc.get("module")):
        src = body.get("source")
        src = src if isinstance(src, str) else ""
        if not (LOCAL_MODULE.match(src) or OWN_RELEASE_MODULE.match(src)):
            out.append(f'{rel}: module "{mname}" source "{src}" is neither local nor this '
                       "repository's release tag")
    return out


def check_chain(docs: dict[str, dict], pol: dict) -> list[str]:
    """Each link of allowed_provisioner_chain must be a module call in the code."""
    if not (ROOT / PROVISIONER_CHAIN_ROOT).is_dir():
        return []
    out, caller = [], PROVISIONER_CHAIN_ROOT
    for name, source in pol["chain"]:
        calls = {(m, b.get("source")) for rel, doc in docs.items()
                 if posixpath.dirname(rel) == caller for m, b in labelled(doc.get("module"))}
        if (name, source) not in calls:
            out.append(f'{caller}: has no module "{name}" with source "{source}", but '
                       "allowed_provisioner_chain in the OPA policy expects it")
        caller = posixpath.normpath(posixpath.join(caller, source))
    return out


def parse(path: Path, is_json: bool):
    text = path.read_text(encoding="utf-8")
    if is_json:
        return json.loads(text)
    try:
        return hcl2.loads(text)
    except Exception:  # noqa: BLE001 - retried once, then the caller fails closed
        joined = LEADING_OPERATOR.sub(" ", text)
        if joined == text:
            raise
        return hcl2.loads(joined)


def main() -> int:
    pol = load_policy()
    provisioner_dir = PROVISIONER_CHAIN_ROOT
    for _, source in pol["chain"]:
        provisioner_dir = posixpath.normpath(posixpath.join(provisioner_dir, source))

    problems: list[str] = []
    docs: dict[str, dict] = {}
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for fname in sorted(filenames):
            is_json = fname.endswith(".tf.json")
            if not (is_json or fname.endswith(".tf")):
                continue
            path = Path(dirpath) / fname
            rel = path.relative_to(ROOT).as_posix()
            try:
                doc = parse(path, is_json)
            except Exception as exc:  # noqa: BLE001 - any parse error fails closed
                problems.append(f"{rel}: cannot parse ({type(exc).__name__}); fail closed")
                continue
            if not isinstance(doc, dict):
                problems.append(f"{rel}: top level is not an object; fail closed")
                continue
            docs[rel] = doc

    # required_providers are module-scoped: one map per directory.
    by_dir: dict[str, dict] = {}
    for rel, doc in docs.items():
        by_dir.setdefault(posixpath.dirname(rel), {}).update(required_providers(doc))
    for rel, doc in docs.items():
        problems += check_doc(rel, doc, by_dir[posixpath.dirname(rel)], pol, provisioner_dir)
    problems += check_chain(docs, pol)

    for p in problems:
        print(f"  ERROR {p}", file=sys.stderr)
    print(f"check-plan-time-exec: {len(docs)} files parsed, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
