#!/usr/bin/env python3
"""Pre-plan gate: no plan/apply-time code execution, no credential redirection.

A plan runs with the workspace's credentials and environment variables
(TFE_TOKEN, SUPABASE_ACCESS_TOKEN, the cloud plan identity). HCP Terraform
evaluates policies/opa/no_plan_time_code_execution.rego only AFTER the plan,
so this check enforces the same rules on the repository source at pull-request
time. It parses every tracked *.tf file (python-hcl2) and *.tf.json file
(json, duplicate keys rejected) and fails on:
  - a tracked symlink or submodule, or a tracked path inside .terraform/ or
    node_modules/ (git does not list the files behind them);
  - a provisioner in a resource block outside the reviewed module (the module
    that the policy's allowed_provisioner_chain reaches from envs/saas) and
    outside TEST_PROVISIONER_ALLOW;
  - a provisioner in a removed block, anywhere (the plan JSON does not render
    removed blocks, so the policy cannot see these);
  - a data block whose type is on the policy's exec_data_types (external,
    http, aws_lambda_invocation), top-level or inside a check block;
  - an action block whose type is not on allowed_action_types;
  - a data "terraform_remote_state" whose backend is not a literal on the
    policy's allowed_remote_state_backends;
  - a provider that is not on the policy's allowed_provider_sources: in
    required_providers (qualified, unqualified or version-only) and as the
    provider of every provider, resource, data, ephemeral and action block;
  - a provider argument or nested block (dynamic blocks included) that matches
    the policy's endpoint_key_pattern and is not in endpoint_key_exceptions;
  - a module source that is neither local nor this repository's release tag,
    or a local source into .terraform/ or node_modules/;
  - a drift between allowed_provisioner_chain and the module calls in the code;
  - a file that does not parse (fail closed, no fallback parse).

One source of truth: the data, action, provider, backend and endpoint lists
and the provisioner chain are READ from
policies/opa/no_plan_time_code_execution*.rego of the repository that holds
this script. A list body must be plain string literals; anything else (a
comprehension, a set expression, a second definition) exits 2. A fork edits
only the allowlist .rego file, and both controls follow.

Exit codes: 0 clean, 1 violations, 2 setup error (parser or git missing,
policy unreadable). PLAN_EXEC_ROOT overrides the tree to scan (tests): it is
read with `git ls-files` when it is a git work tree, else walked.
PLAN_EXEC_POLICY_DIR overrides the policy folder (tests).
"""
from __future__ import annotations

import json
import os
import posixpath
import re
import subprocess
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
TEST_ROOT = os.environ.get("PLAN_EXEC_ROOT")
ROOT = Path(TEST_ROOT or REPO).resolve()
# PLAN_EXEC_POLICY_DIR replaces the policy folder (tests of the .rego reader).
POLICY_DIR = Path(os.environ.get("PLAN_EXEC_POLICY_DIR") or REPO / "policies" / "opa").resolve()
POLICY = POLICY_DIR / "no_plan_time_code_execution.rego"
ALLOWLIST = POLICY_DIR / "no_plan_time_code_execution_allowlist.rego"
POLICY_PACKAGE = "terraform.policies.no_plan_time_code_execution"
SKIP_DIRS = {".git", ".terraform", "node_modules"}
# Folders whose content a git checkout or a TFC run does not review.
HIDDEN_SEGMENTS = {".terraform", "node_modules"}

# The root whose module calls start the policy's allowed_provisioner_chain.
PROVISIONER_CHAIN_ROOT = "envs/saas"
# Test fixtures that never run in an HCP Terraform workspace, so the policy
# never sees them: {file: {resource address}}. tests/e2e/aws runs only through
# `terraform test` in .github/workflows/sandbox-e2e.yml (sandbox account); its
# fixed `sleep 20` waits for S3 bucket settings to become consistent.
TEST_PROVISIONER_ALLOW = {"tests/e2e/aws/main.tf": {"terraform_data.archive_settle"}}

LOCAL_MODULE = re.compile(r"\.\.?/.*", re.S)
OWN_RELEASE_MODULE = re.compile(
    r"git::https://github\.com/EdwinKassier/Ashes-Devops-Tools\.git//modules/[a-z0-9/_-]+"
    r"\?ref=v[0-9]+\.[0-9]+\.[0-9]+"
)
DEFAULT_REGISTRY = "registry.terraform.io"
BUILTIN_TERRAFORM = "terraform.io/builtin/terraform"
TYPED_BLOCKS = ("resource", "data", "ephemeral", "action")

# A rego list body this script accepts: string literals, commas, whitespace
# and comments, nothing else.
STRING_SET_BODY = re.compile(r'(?:\s|,|"[^"\\\n]*"|#[^\n]*)*')
CHAIN_BODY = re.compile(
    r'(?:\s|,|#[^\n]*|\{"name":\s*"[^"\\\n]*",\s*"source":\s*"[^"\\\n]*"\})*'
)


def show(path: Path) -> str:
    try:
        return path.relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def setup_error(msg: str) -> None:
    sys.stderr.write(f"check-plan-time-exec: {msg}\n")
    sys.exit(2)


# --- read the lists from the OPA policy ------------------------------------
def _rego_rule(text: str, name: str, src: Path) -> str:
    """Right-hand side of the one top-level `name := ...` rule, up to the next
    top-level line that is not a closing bracket (or the end of the file)."""
    m = re.search(rf"^{re.escape(name)}\s*:=\s*(.*?)(?=^[^\s\]}}]|\Z)", text, re.M | re.S)
    if not m:
        setup_error(f"cannot read {name} from {show(src)}")
    return m.group(1).strip()


def rego_string_set(text: str, name: str, src: Path, allow_empty: bool = False) -> set[str]:
    rhs = _rego_rule(text, name, src)
    if allow_empty and rhs == "set()":
        return set()
    if not (rhs.startswith("{") and rhs.endswith("}") and STRING_SET_BODY.fullmatch(rhs[1:-1])):
        setup_error(f"{name} in {show(src)} must be a set of string literals, "
                    "with no expressions or comprehensions")
    values = set(re.findall(r'"([^"]*)"', re.sub(r"#[^\n]*", "", rhs)))
    if not values and not allow_empty:
        setup_error(f"{name} in {show(src)} is empty")
    return values


def rego_chain(text: str, src: Path) -> list[tuple[str, str]]:
    rhs = _rego_rule(text, "allowed_provisioner_chain", src)
    if not (rhs.startswith("[") and rhs.endswith("]") and CHAIN_BODY.fullmatch(rhs[1:-1])):
        setup_error(f"allowed_provisioner_chain in {show(src)} must be a list of "
                    '{"name": "...", "source": "..."} literals')
    chain = re.findall(r'\{"name":\s*"([^"]+)",\s*"source":\s*"([^"]+)"\}', rhs)
    if not chain:
        setup_error(f"allowed_provisioner_chain in {show(src)} is empty")
    return chain


def single_definitions(names: list[str]) -> None:
    """Each list must be defined exactly once across the policy package, so an
    extra `name contains ...` or `name := ...` elsewhere cannot widen OPA
    without this script seeing it."""
    texts = []
    for f in sorted(POLICY_DIR.glob("*.rego")):
        if f.name.endswith("_test.rego"):
            continue
        t = f.read_text(encoding="utf-8")
        if re.search(rf"^package\s+{re.escape(POLICY_PACKAGE)}\s*$", t, re.M):
            texts.append(t)
    for name in names:
        n = sum(len(re.findall(rf"^{re.escape(name)}\b", t, re.M)) for t in texts)
        if n != 1:
            setup_error(f"{name} is defined {n} times in package {POLICY_PACKAGE}; "
                        "it must be defined exactly once")


def load_policy() -> dict:
    try:
        policy = POLICY.read_text(encoding="utf-8")
        allow = ALLOWLIST.read_text(encoding="utf-8")
    except OSError as exc:
        setup_error(f"cannot read the OPA policy: {exc}")
    single_definitions(["exec_data_types", "endpoint_key_pattern", "allowed_provisioner_chain",
                        "allowed_provider_sources", "endpoint_key_exceptions",
                        "allowed_remote_state_backends", "allowed_action_types"])
    m = re.search(r"^endpoint_key_pattern\s*:=\s*`([^`]+)`\s*$", policy, re.M)
    if not m:
        setup_error(f"endpoint_key_pattern in {show(POLICY)} must be one raw string")
    return {
        "exec_data_types": rego_string_set(policy, "exec_data_types", POLICY),
        "endpoint_key": re.compile(m.group(1)),
        "chain": rego_chain(policy, POLICY),
        "providers": rego_string_set(allow, "allowed_provider_sources", ALLOWLIST),
        "endpoint_exceptions": rego_string_set(allow, "endpoint_key_exceptions", ALLOWLIST),
        "backends": rego_string_set(allow, "allowed_remote_state_backends", ALLOWLIST),
        "actions": rego_string_set(allow, "allowed_action_types", ALLOWLIST, allow_empty=True),
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


def hidden_path(path: str) -> bool:
    return bool(HIDDEN_SEGMENTS & set(path.split("/")))


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
            out.append(f'{rel}: data "{rtype}" "{name}" runs code or calls out at plan time '
                       "with the workspace's credentials and environment")
        if kind == "action" and rtype not in pol["actions"]:
            out.append(f'{rel}: action "{rtype}" "{name}" is not on allowed_action_types '
                       "(an action runs provider code at apply time)")
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
                out.append(f'{rel}: provider "{pname}" sets "{key}" (an endpoint, proxy, TLS or '
                           "credential override can send the workspace's credentials to another host)")

    for mname, body in labelled(doc.get("module")):
        src = body.get("source")
        src = src if isinstance(src, str) else ""
        if not (LOCAL_MODULE.fullmatch(src) or OWN_RELEASE_MODULE.fullmatch(src)):
            out.append(f'{rel}: module "{mname}" source "{src}" is neither local nor this '
                       "repository's release tag")
        elif LOCAL_MODULE.fullmatch(src) and hidden_path(
                posixpath.normpath(posixpath.join(posixpath.dirname(rel), src))):
            out.append(f'{rel}: module "{mname}" source "{src}" points into .terraform/ or '
                       "node_modules/, which this check does not scan")
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


def _no_duplicate_keys(pairs):
    seen = {}
    for k, v in pairs:
        if k in seen:
            raise ValueError(f"duplicate JSON key {k!r}")
        seen[k] = v
    return seen


def parse(path: Path, is_json: bool):
    text = path.read_text(encoding="utf-8")
    if is_json:
        return json.loads(text, object_pairs_hook=_no_duplicate_keys)
    return hcl2.loads(text)


def is_tf(name: str) -> bool:
    return name.endswith(".tf") or name.endswith(".tf.json")


def discover() -> tuple[list[str], list[str]]:
    """(files to parse, problems). Git mode lists tracked files only: that is
    what a VCS-driven run checks out."""
    if not TEST_ROOT or (ROOT / ".git").exists():
        try:
            raw = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-s", "-z"],
                                 check=True, capture_output=True).stdout.decode("utf-8")
        except (OSError, subprocess.CalledProcessError) as exc:
            setup_error(f"git ls-files failed in {ROOT}: {exc}")
        files, problems = [], []
        for entry in filter(None, raw.split("\0")):
            meta, path = entry.split("\t", 1)
            mode = meta.split(" ", 1)[0]
            if mode == "120000":
                problems.append(f"{path}: tracked symlink (the files behind it are not scanned)")
            elif mode == "160000":
                problems.append(f"{path}: submodule (its files are not scanned)")
            elif hidden_path(path):
                problems.append(f"{path}: tracked file inside .terraform/ or node_modules/")
            elif is_tf(path):
                files.append(path)
        return sorted(files), problems
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        files += [(Path(dirpath) / f).relative_to(ROOT).as_posix() for f in filenames if is_tf(f)]
    return sorted(files), []


def main() -> int:
    pol = load_policy()
    provisioner_dir = PROVISIONER_CHAIN_ROOT
    for _, source in pol["chain"]:
        provisioner_dir = posixpath.normpath(posixpath.join(provisioner_dir, source))

    files, problems = discover()
    docs: dict[str, dict] = {}
    for rel in files:
        try:
            doc = parse(ROOT / rel, rel.endswith(".tf.json"))
        except Exception as exc:  # noqa: BLE001 - any parse error fails closed
            problems.append(f"{rel}: cannot parse ({type(exc).__name__}: {str(exc)[:120]}); fail closed")
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
