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
  - a data or ephemeral block whose type is on the policy's exec_data_types
    (external, http, aws_lambda_invocation), top-level or inside a check block;
  - an archive_file whose source is not a literal source_file under
    path.module (re-audit 5 SEC-2: it can zip /proc/self/environ);
  - a path-reading resource or data argument (path_reading_attributes: S3,
    GCS and Lambda uploads, tfe_slug) that is not a literal path under
    path.module or an archive_file output_path, and any refused upload
    argument (refused_path_attributes) (re-audit 7 SEC-1 to SEC-3);
  - an ephemeral block whose type is not on allowed_ephemeral_types (the plan
    JSON does not render ephemeral blocks, so this is the only layer that sees
    one that nothing references);
  - an action block whose type is not on allowed_action_types;
  - a data "terraform_remote_state" whose backend is not a literal on the
    policy's allowed_remote_state_backends, or whose config is not an object
    literal with only the keys organization and workspaces (workspaces: name
    or prefix), so no hostname or token can send the run's token elsewhere;
  - a provider that is not on the policy's allowed_provider_sources: in
    required_providers (qualified, unqualified or version-only) and as the
    provider of every provider, resource, data, ephemeral and action block;
  - a provider argument or nested block (dynamic blocks included) that matches
    the policy's endpoint_key_pattern and is not in endpoint_key_exceptions;
  - a provider argument that matches credential_key_pattern (profile, shared
    config / credentials files, static keys and tokens, impersonation) unless
    it is null or an expression whose only references are on
    allowed_credential_references for that provider type and argument, whose
    only string literals are on allowed_credential_literals, and which uses no
    function; a variable it reads must declare no default other than null or
    a bool, and must have the type on allowed_credential_variable_types,
    wherever it is declared; nested or dynamic credential blocks always fail;
  - a tracked *.tfvars / *.tfvars.json file that sets a variable an allowed
    credential form reads;
  - an override file (override.tf, *_override.tf, .tf.json), except a fork's
    envs/**/backend_override.tf that holds only terraform { backend / cloud };
  - a non-local module source under envs/ (HCP Terraform runs envs/);
  - file(), templatefile() and the other file readers with a literal path
    that is not under path.module / path.root or leaves the repository, a
    path built by a function or expression, and (SEC-1) a path that is a
    reference or holds an interpolation, except the reviewed config loaders
    on FILE_READERS (a reference's value is not known here, so
    file(var.x) with x = /proc/self/environ would read the runner's
    environment);
  - elsewhere, a module source that is neither local nor this repository's
    release tag, or a local source into .terraform/ or node_modules/;
  - a drift between allowed_provisioner_chain and the module calls in the code;
  - a file that does not parse (fail closed, no fallback parse).

One source of truth: the data, action, provider, backend and endpoint lists
and the provisioner chain are READ from
policies/opa/no_plan_time_code_execution*.rego of the repository that holds
this script. A list body must be plain string literals; anything else (a
comprehension, a set expression, a second definition) exits 2. A fork edits
only the allowlist .rego file, and both controls follow.

Exit codes: 0 clean, 1 violations, 2 setup error (parser or git missing,
policy unreadable). With PLAN_EXEC_TEST=1 only (tests), PLAN_EXEC_ROOT overrides the tree to scan: it is
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

# Re-audit 6 SEC-2: run as `python3 -P` so a file beside this script (for
# example a platform-owned scripts/hcl2.py or scripts/json.py) cannot shadow a
# module. Without -P, sys.path[0] is this directory: fail closed.
if not sys.flags.safe_path and sys.path and \
        Path(sys.path[0] or ".").resolve() == Path(__file__).resolve().parent:
    sys.stderr.write("check-plan-time-exec: run with `python3 -P` (the script directory must "
                     "not be on sys.path, so no file beside it can replace a module)\n")
    sys.exit(2)

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
# Re-audit 7 CICD-4: the test knobs act only with PLAN_EXEC_TEST=1 (the
# test script sets it; CI and make never do), so a caller cannot point the
# gate at a clean copy of the tree or at other allowlists. PYTHONPATH could
# replace hcl2 even under -P, so it is refused.
_TESTING = os.environ.get("PLAN_EXEC_TEST") == "1"
if not _TESTING and (os.environ.get("PLAN_EXEC_ROOT") or os.environ.get("PLAN_EXEC_POLICY_DIR")):
    sys.stderr.write("check-plan-time-exec: PLAN_EXEC_ROOT / PLAN_EXEC_POLICY_DIR are test-only "
                     "(PLAN_EXEC_TEST=1); refusing to scan anything but this repository\n")
    sys.exit(2)
if os.environ.get("PYTHONPATH"):
    sys.stderr.write("check-plan-time-exec: PYTHONPATH is set; unset it (it could replace a module "
                     "this check imports)\n")
    sys.exit(2)
TEST_ROOT = os.environ.get("PLAN_EXEC_ROOT") if _TESTING else None
ROOT = Path(TEST_ROOT or REPO).resolve()
# PLAN_EXEC_POLICY_DIR replaces the policy folder (tests of the .rego reader).
POLICY_DIR = Path((os.environ.get("PLAN_EXEC_POLICY_DIR") if _TESTING else None) or REPO / "policies" / "opa").resolve()
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
# "<provider type>/<argument>=<var.|local.><name>[.<attr>|[*]]..."
CRED_REF_ENTRY = re.compile(
    r"([a-z0-9-]+)/([a-z0-9_]+)=((?:var|local)\.[A-Za-z_][A-Za-z0-9_-]*)((?:\.[A-Za-z_][A-Za-z0-9_-]*|\[\*\])*)"
)
# "<variable name>=<type>"
CRED_TYPE_ENTRY = re.compile(r"([A-Za-z_][A-Za-z0-9_-]*)=(.+)")
# A type compared token by token: identifiers and parentheses. python-hcl2
# renders object({a = string}) as ${object({"a": "string"})}; both give the
# same tokens, and an optional() default adds tokens.
TYPE_TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*|[()]")
# Functions that read a file on the runner; their result can reach state,
# outputs or an API call. fileexists (a bool) is not listed.
FILE_FUNCTION = re.compile(
    r"(?<![\w.])(file|filebase64|filesha1|filesha256|filesha512|filemd5|filebase64sha256|"
    r"filebase64sha512|templatefile|fileset)\(\s*"
)
FILE_ARG_REFERENCE = re.compile(
    r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_-]*|\[[^\[\]()]*\])*\s*[,)]"
)
# SEC-1: the reviewed file readers whose path is a reference or holds an
# interpolation. Re-audit 5 showed that matching the call text is not enough
# (file(f) with f bound to /proc/self/environ passed), so each reader is pinned
# to its whole expression, the locals that bind its path, and the validations
# of the variable it reads. python-hcl2 (pinned with hashes) renders each
# expression as below; any other text, or a second definition, fails.
#   - every root's config loader (envs/** and templates/** config.tf): reads
#     landing_zone_config_path, which may only be a relative .yaml path that
#     stays in the repository;
#   - tfc-admin's workspace_variables_file reader (relative .yaml only);
#   - gcp-workload's preset loader (names must match ^[a-z0-9-]+$).
_LZF = ('${var.landing_zone_config_path == "" ? null : (var.landing_zone_config_path == null ? '
        '"${path.root}/%s/config/landing-zone.yaml" : (startswith(var.landing_zone_config_path, "/") ? '
        'var.landing_zone_config_path : "${path.root}/${var.landing_zone_config_path}"))}')
# The exact validation conditions (python-hcl2 renders null as None). A
# condition that merely contains these checks (true || ...) does not match.
_YAML_RE = 'can(regex("^[A-Za-z0-9_./-]+\\\\.ya?ml$", coalesce(%s, "x")))'
_LZP_SHAPE = ('${var.landing_zone_config_path == None || var.landing_zone_config_path == "" || ('
              + _YAML_RE % "var.landing_zone_config_path"
              + ' && !startswith(coalesce(var.landing_zone_config_path, "x"), "/") && length([for s in '
              'split("/", dirname("./${coalesce(var.landing_zone_config_path, "x")}/_")) : s if s == ".."]) '
              '<= %d)}')
_WVF_SHAPE = ('${var.workspace_variables_file == None || ('
              + _YAML_RE % "var.workspace_variables_file"
              + ' && !startswith(coalesce(var.workspace_variables_file, "x"), "/"))}')
_ESCAPE = ('${startswith(coalesce(%s, "/"), "/") || !(dirname("./${coalesce(%s, "x")}/_") == ".." || '
           'dirname("./${coalesce(%s, "x")}/_") == "../../.." || startswith(dirname("./${coalesce(%s, "x")}/_"), '
           '"../../../") || (startswith(dirname("./${coalesce(%s, "x")}/_"), "../") && '
           '!startswith(dirname("./${coalesce(%s, "x")}/_"), "../../")))}')
FILE_READERS = (
    {
        "path": re.compile(r"^(?:envs/(?:aws/|gcp/)?[a-z-]+|templates/[a-z/-]+)/config\.tf$"),
        "carrier": ("lz_documents",
                    '${[for f in compact([${local.landing_zone_config_file != None && '
                    'fileexists(coalesce(local.landing_zone_config_file, "/nonexistent")) ? '
                    'local.landing_zone_config_file : ""}]) : yamldecode(file(f))]}'),
        # Depth-tied (re-audit 5 review): a root at depth d may climb d levels
        # only, so a depth-2 root cannot take the depth-3 shape.
        "pins": {"landing_zone_config_file": lambda d: {_LZF % "/".join([".."] * d)}},
        "var": ("landing_zone_config_path", lambda d: [{_LZP_SHAPE % d}]),
    },
    {
        "path": re.compile(r"^envs/tfc-admin/main\.tf$"),
        "carrier": ("workspace_variables_file_raw",
                    '${local.workspace_variables_file_present ? '
                    'yamldecode(file(local.workspace_variables_file_path)) : {}}'),
        "pins": {
            "workspace_variables_file_path": {
                '${var.workspace_variables_file == null ? null : (startswith(var.workspace_variables_file, "/") ? '
                'var.workspace_variables_file : "${path.root}/${var.workspace_variables_file}")}'},
            "workspace_variables_file_present": {
                '${local.workspace_variables_file_path != None && '
                'fileexists(coalesce(local.workspace_variables_file_path, "/nonexistent"))}'},
        },
        "var": ("workspace_variables_file", [{_WVF_SHAPE}, {_ESCAPE % (("var.workspace_variables_file",) * 6)}]),
    },
    {
        "path": re.compile(r"^envs/gcp/workload/config\.tf$"),
        "carrier": ("preset_documents",
                    '${[for n in local.preset_names : yamldecode(file("${path.root}/../../../examples/'
                    'presets/${n}.yaml")) if can(regex("^[a-z0-9-]+$", n))]}'),
        "pins": {},
        "var": None,
    },
)
# path.module and path.root are safe references (fileset's first argument).
SAFE_FILE_REFERENCES = {"path.module", "path.root"}
# SEC-2: the only keys a terraform_remote_state config may set.
REMOTE_STATE_CONFIG_KEYS = {"organization", "workspaces"}
REMOTE_STATE_WORKSPACE_KEYS = {"name", "prefix"}
OVERRIDE_FILE = re.compile(r"(?:^|_)override\.tf(?:\.json)?$")
# A fork's own state backend (UPGRADING.md "What you own").
BACKEND_OVERRIDE = "backend_override.tf"
# A var. or local. reference with its attribute and literal-index path. python-hcl2
# renders the expression as text; a nested list element as '${...}'.
REFERENCE = re.compile(
    r"(?<![\w.])((?:var|local)\.[A-Za-z_][A-Za-z0-9_-]*)"
    r"(?:\.[A-Za-z_][A-Za-z0-9_-]*|\[(?:\"[^\"\\]*\"|[0-9]+)\])*"
)
# What may remain of an allowed credential expression once its references (R)
# and allowed literals (L) are taken out: null, bools, comparisons,
# conditionals, brackets. No function call, no other reference, no literal.
CREDENTIAL_REST = re.compile(r"(?:\s+|R|L|null|true|false|\?|:|==|!=|&&|\|\||!|\[|\]|\(|\)|,)*")
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
    single_definitions(["exec_data_types", "endpoint_key_pattern", "credential_key_pattern",
                        "allowed_provisioner_chain", "allowed_provider_sources",
                        "endpoint_key_exceptions", "allowed_remote_state_backends",
                        "allowed_action_types", "allowed_credential_references",
                        "allowed_credential_literals", "allowed_ephemeral_types",
                        "allowed_credential_variable_types", "path_reading_attributes",
                        "refused_path_attributes"])
    patterns = {}
    for name in ("endpoint_key_pattern", "credential_key_pattern"):
        m = re.search(rf"^{name}\s*:=\s*`([^`]+)`\s*$", policy, re.M)
        if not m:
            setup_error(f"{name} in {show(POLICY)} must be one raw string")
        patterns[name] = re.compile(m.group(1))
    cred_refs: dict[tuple[str, str], list[re.Pattern]] = {}
    cred_vars: set[str] = set()
    for entry in rego_string_set(allow, "allowed_credential_references", ALLOWLIST):
        m = CRED_REF_ENTRY.fullmatch(entry)
        if not m:
            setup_error(f"allowed_credential_references entry {entry!r} in {show(ALLOWLIST)} must "
                        'be "<provider type>/<argument>=<var.|local.><name>[.<attr>|[*]]..."')
        path = re.escape(m.group(3) + m.group(4)).replace(r"\[\*\]", r'\["[A-Za-z0-9_-]+"\]')
        cred_refs.setdefault((m.group(1), m.group(2)), []).append(re.compile(path))
        if m.group(3).startswith("var."):
            cred_vars.add(m.group(3)[4:])
    cred_types: dict[str, list[str]] = {}
    for entry in rego_string_set(allow, "allowed_credential_variable_types", ALLOWLIST):
        m = CRED_TYPE_ENTRY.fullmatch(entry)
        if not m:
            setup_error(f"allowed_credential_variable_types entry {entry!r} must be \"<name>=<type>\"")
        cred_types[m.group(1)] = TYPE_TOKEN.findall(m.group(2))
    if cred_vars - set(cred_types):
        setup_error(f"allowed_credential_variable_types in {show(ALLOWLIST)} lacks "
                    f"{sorted(cred_vars - set(cred_types))}")
    return {
        "exec_data_types": rego_string_set(policy, "exec_data_types", POLICY),
        "endpoint_key": patterns["endpoint_key_pattern"],
        "credential_key": patterns["credential_key_pattern"],
        "credential_refs": cred_refs,
        "credential_vars": cred_vars,
        "credential_types": cred_types,
        "credential_literals": rego_string_set(allow, "allowed_credential_literals", ALLOWLIST),
        "ephemeral": rego_string_set(allow, "allowed_ephemeral_types", ALLOWLIST, allow_empty=True),
        "chain": rego_chain(policy, POLICY),
        "providers": rego_string_set(allow, "allowed_provider_sources", ALLOWLIST),
        "endpoint_exceptions": rego_string_set(allow, "endpoint_key_exceptions", ALLOWLIST),
        "backends": rego_string_set(allow, "allowed_remote_state_backends", ALLOWLIST),
        "actions": rego_string_set(allow, "allowed_action_types", ALLOWLIST, allow_empty=True),
        "path_attrs": rego_string_set(allow, "path_reading_attributes", ALLOWLIST),
        "refused_attrs": rego_string_set(allow, "refused_path_attributes", ALLOWLIST),
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


NO_DEFAULT = object()


def variable_blocks(doc: dict):
    """Yield (name, body) for every variable block."""
    for name, body in labelled(doc.get("variable")):
        yield name, body


def credential_variable_problem(name: str, pol: dict, dir_vars: dict) -> str | None:
    """The variable an allowed form reads: declared here, with the canonical
    type and a null or bool default."""
    body = dir_vars.get(name)
    if body is None:
        return f"var.{name}, which is not declared in this directory"
    rendered = body.get("type")
    if not isinstance(rendered, str) or TYPE_TOKEN.findall(rendered) != pol["credential_types"].get(name):
        return (f"var.{name}, whose type is not the one on allowed_credential_variable_types "
                "(an optional() default would carry a value the plan does not show)")
    default = body.get("default", NO_DEFAULT)
    if default is not NO_DEFAULT and default is not None and not isinstance(default, bool):
        return f"var.{name}, whose default gives it a value of its own"
    return None


def credential_problem(value, allowed: list, pol: dict, dir_vars: dict) -> str | None:
    """None when a credential argument's value is null or an allowed form, else why not."""
    if value is None:
        return None
    if isinstance(value, list) and value and all(
            isinstance(v, str) and v.startswith("${") and v.endswith("}") for v in value):
        # A list of interpolations: [var.x.default.shared_config_file].
        for v in value:
            why = credential_problem(v, allowed, pol, dir_vars)
            if why:
                return why
        return None
    if not (isinstance(value, str) and value.startswith("${") and value.endswith("}")):
        return "a literal value"
    if not allowed:
        return "an expression (no form of this argument is allowed)"
    expr = value[2:-1]
    refs = list(REFERENCE.finditer(expr))
    for m in refs:
        if not any(p.fullmatch(m.group(0)) for p in allowed):
            return f"a reference to {m.group(0)}, which is not an exact path on allowed_credential_references"
    for root in sorted({m.group(1) for m in refs if m.group(1).startswith("var.")}):
        why = credential_variable_problem(root[4:], pol, dir_vars)
        if why:
            return why
    rest = REFERENCE.sub("R", expr)
    while "'${R}'" in rest:
        rest = rest.replace("'${R}'", "R")
    for lit in pol["credential_literals"]:
        rest = rest.replace(f'"{lit}"', "L")
    if not CREDENTIAL_REST.fullmatch(rest):
        return "a literal, function call or other reference beside the allowed references"
    return None


def check_doc(rel: str, doc: dict, dir_providers: dict, pol: dict, provisioner_dir: str,
              dir_vars: dict | None = None, dir_locals: dict | None = None) -> list[str]:
    dir_vars = dir_vars or {}
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
        if kind in ("data", "ephemeral") and rtype in pol["exec_data_types"]:
            out.append(f'{rel}: {kind} "{rtype}" "{name}" runs code or calls out at plan time '
                       "with the workspace's credentials and environment")
        if kind in ("data", "resource"):
            out += path_attribute_problems(rel, rtype, name, body, pol)
        if rtype == "archive_file" and kind in ("data", "resource"):
            out += archive_problems(rel, name, body)
        if kind == "ephemeral" and rtype not in pol["ephemeral"]:
            out.append(f'{rel}: ephemeral "{rtype}" "{name}" is not on allowed_ephemeral_types '
                       "(an ephemeral resource runs provider code during the plan and the apply; "
                       "the plan JSON does not show it, so the OPA policy cannot see it)")
        if kind == "action" and rtype not in pol["actions"]:
            out.append(f'{rel}: action "{rtype}" "{name}" is not on allowed_action_types '
                       "(an action runs provider code at apply time)")
        if kind == "data" and rtype == "terraform_remote_state" \
                and literal(body.get("backend")) not in pol["backends"]:
            out.append(f"{rel}: data.terraform_remote_state.{name} backend must be a literal "
                       f"{sorted(pol['backends'])}, not {body.get('backend')!r}")
        if kind == "data" and rtype == "terraform_remote_state":
            out += remote_state_config_problems(rel, name, body.get("config"))
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
        ptype = src.rsplit("/", 1)[-1]
        nested = {k for v in body.values() for k in all_keys(v)}
        for key in sorted((set(body) | nested)):
            if not pol["credential_key"].match(key):
                continue
            value = body.get(key)
            if key in nested or isinstance(value, dict) or (
                    isinstance(value, list) and any(isinstance(v, dict) for v in value)):
                why = "a nested or dynamic block"
            else:
                why = credential_problem(value, pol["credential_refs"].get((ptype, key), []),
                                         pol, dir_vars)
            if why:
                out.append(f'{rel}: provider "{pname}" sets "{key}" to {why} (a profile, credentials '
                           "file, token or impersonation argument can run a command or swap the "
                           "workspace's identity; only the forms on allowed_credential_references may)")

    for mname, body in labelled(doc.get("module")):
        src = body.get("source")
        src = src if isinstance(src, str) else ""
        if rel.startswith("envs/") and not LOCAL_MODULE.fullmatch(src):
            out.append(f'{rel}: module "{mname}" source "{src}" is not local; HCP Terraform runs '
                       "envs/ and this check does not scan the code behind a remote source")
        elif not (LOCAL_MODULE.fullmatch(src) or OWN_RELEASE_MODULE.fullmatch(src)):
            out.append(f'{rel}: module "{mname}" source "{src}" is neither local nor this '
                       "repository's release tag")
        elif LOCAL_MODULE.fullmatch(src) and hidden_path(
                posixpath.normpath(posixpath.join(posixpath.dirname(rel), src))):
            out.append(f'{rel}: module "{mname}" source "{src}" points into .terraform/ or '
                       "node_modules/, which this check does not scan")

    # A variable that an allowed credential form reads, wherever it is declared.
    for vname, _ in variable_blocks(doc):
        if vname in pol["credential_vars"]:
            why = credential_variable_problem(vname, pol, dict(variable_blocks(doc)))
            if why:
                out.append(f'{rel}: variable "{vname}": {why}')

    out += file_function_problems(rel, doc, dir_locals, dir_vars)
    out += override_problems(rel, doc)
    return out


def all_strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield str(k)
            yield from all_strings(v)
    elif isinstance(node, list):
        for v in node:
            yield from all_strings(v)


def string_literal(text: str, start: int) -> str | None:
    """The body of the string literal that opens at text[start] ('"'), with
    its ${...} parts kept; None when it does not close."""
    i, depth = start + 1, 0
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if text.startswith("${", i):
            depth += 1
            i += 2
            continue
        if c == "}" and depth:
            depth -= 1
        elif c == '"' and not depth:
            return text[start + 1:i]
        i += 1
    return None


ARCHIVE_OUTPUT_REF = re.compile(r"^\$\{data\.archive_file\.[A-Za-z_][A-Za-z0-9_-]*(?:\[[0-9]+\])?\.output_path\}$")


def path_attribute_problems(rel: str, rtype: str, name: str, body: dict, pol: dict) -> list[str]:
    """Re-audit 7 SEC-1 to SEC-3: a path-reading argument holds a literal path
    under path.module in the repository, or a reviewed archive_file's
    output_path; a refused argument is never set."""
    out = []
    for attr, value in body.items():
        key = f"{rtype}.{attr}"
        if key in pol["refused_attrs"]:
            out.append(f'{rel}: {rtype} "{name}" sets {attr}, which uploads local files and is '
                       "not allowed (refused_path_attributes)")
        elif key in pol["path_attrs"]:
            ok = isinstance(value, str) and (
                ARCHIVE_OUTPUT_REF.match(value)
                or (ARCHIVE_SOURCE.match(value) and "%{" not in value and not posixpath.normpath(
                    posixpath.join(posixpath.dirname(rel), value[len("${path.module}"):].lstrip("/"))).startswith("..")))
            if not ok:
                out.append(f'{rel}: {rtype} "{name}" {attr} reads a path on the runner and uploads '
                           f"it; use a literal path under path.module or a data.archive_file "
                           f"output_path, not {value!r}")
    return out


ARCHIVE_SOURCE = re.compile(r"^\$\{path\.module\}/[A-Za-z0-9_./-]+$")


def archive_problems(rel: str, name: str, body: dict) -> list[str]:
    """Re-audit 5 SEC-2: archive_file reads any runner file into a zip that
    filebase64() can return; only a literal source_file under path.module that
    stays in the repository is allowed."""
    where = f'{rel}: archive_file "{name}"'
    extra = sorted(set(map(str, body)) & {"source_dir", "source", "source_content", "source_content_filename"})
    if extra:
        return [f"{where} sets {extra}; only source_file under path.module is allowed"]
    src = body.get("source_file")
    if not isinstance(src, str) or not ARCHIVE_SOURCE.match(src) or \
            posixpath.normpath(posixpath.join(posixpath.dirname(rel), src[len("${path.module}"):].lstrip("/"))).startswith(".."):
        return [f"{where} source_file must be a literal path under path.module in the repository, "
                f"not {src!r} (it reads files on the runner at plan time)"]
    return []


def remote_state_config_problems(rel: str, name: str, config) -> list[str]:
    """SEC-2: a remote-state config must be an object literal with only the
    keys organization and workspaces, so a hostname (or token) cannot send
    the run's HCP Terraform token to another host during the plan."""
    where = f"{rel}: data.terraform_remote_state.{name} config"
    if config is None:
        return []
    if not isinstance(config, dict):
        return [f"{where} must be an object literal with only {sorted(REMOTE_STATE_CONFIG_KEYS)}, "
                "not an expression (a built config could set hostname)"]
    out = []
    extra = sorted(set(map(str, config)) - REMOTE_STATE_CONFIG_KEYS)
    if extra:
        out.append(f"{where} sets {extra}; only {sorted(REMOTE_STATE_CONFIG_KEYS)} are allowed "
                   "(hostname or token would send the run's token to another host)")
    ws = config.get("workspaces")
    if ws is not None and not (isinstance(ws, dict) and set(map(str, ws)) <= REMOTE_STATE_WORKSPACE_KEYS):
        out.append(f"{where}.workspaces must be an object literal with only "
                   f"{sorted(REMOTE_STATE_WORKSPACE_KEYS)}")
    return out


# Re-audit 6 SEC-1: any file-function name anywhere in a template fails. A
# scan of the ${...} parts only lost twice (a "#" or "}" inside a string
# literal hid the call), so no attempt is made to parse the template.
TEMPLATE_TOKEN = re.compile(r"(?<![\w.])(?:file\w*|templatefile|templatestring)(?!\w)")


def template_problems(rel: str, fn: str, lit: str, suffix: str) -> list[str]:
    """Re-audit 5 review: a templatefile() template is code too. Terraform lets
    a template call file(), so a .tftpl holding ${file("/proc/self/environ")}
    reads the runner's environment. The template must exist in the repository
    and must not name a file function anywhere (re-audit 6: string literals
    hid calls from an expression scan)."""
    path = ROOT / posixpath.normpath(posixpath.join(posixpath.dirname(rel), "." + suffix))
    try:
        body = path.read_text()
    except (OSError, UnicodeDecodeError):
        return [f'{rel}: {fn}("{lit}") reads a template this check cannot read; fail closed']
    if TEMPLATE_TOKEN.search(body):
        return [f'{rel}: {fn}("{lit}") renders a template that names a file function '
                "(file, filebase64, templatefile, ...): it could read files on the runner"]
    return []


def reader_problems(rel: str, text: str, dir_locals: dict, dir_vars: dict) -> list[str] | None:
    """None when text is the whole expression of a reviewed reader of rel and
    its path bindings and variable validations are the reviewed ones; else
    the reasons (an empty list is never returned)."""
    for r in FILE_READERS:
        name, canon = r["carrier"]
        if not r["path"].match(rel) or text != canon:
            continue
        out = []
        depth = rel.count("/")
        pins = {k: (v(depth) if callable(v) else v) for k, v in r["pins"].items()}
        for lname, allowed in [(name, {canon})] + list(pins.items()):
            defs = dir_locals.get(lname, [])
            if len(defs) != 1 or defs[0] not in allowed:
                out.append(f"{rel}: local.{lname} is not the reviewed definition, so the path "
                           f"that {name} reads is not pinned")
        if r["var"]:
            vname, groups = r["var"]
            groups = groups(depth) if callable(groups) else groups
            conds = {str(v.get("condition", "")) for v in blocks(dir_vars.get(vname, {}).get("validation"))}
            for group in groups:
                if not conds & group:
                    out.append(f"{rel}: variable {vname} lacks the reviewed path validation "
                               "(relative .yaml inside the repository), so "
                               f"{name} could read a file on the runner")
        return out or None
    return ["not a reviewed reader"]


def file_function_problems(rel: str, doc: dict, dir_locals: dict | None = None,
                           dir_vars: dict | None = None) -> list[str]:
    """file(), templatefile() and the other file readers must read a literal
    path under path.module / path.root that stays in the repository and holds
    no interpolation. A reference, or an interpolated path, is allowed only
    for a reviewed reader on FILE_READERS whose whole expression, path locals
    and variable validations match (SEC-1)."""
    dir_locals, dir_vars = dir_locals or {}, dir_vars or {}
    out = []
    for text in all_strings(doc):
        for m in FILE_FUNCTION.finditer(text):
            fn, at = m.group(1), m.end()
            if text.startswith('"', at):
                lit = string_literal(text, at)
                # Review of the re-audit 6 fixes: Terraform evaluates %{ } directives
                # (and the $${ / %%{ escapes) in a quoted path, so the path this
                # check resolves is not the one Terraform reads.
                if lit is not None and ("%{" in lit or "$${" in lit or "%%{" in lit):
                    out.append(f'{rel}: {fn}("{lit}") holds a template directive or escape in '
                               "its path, which Terraform evaluates and this check does not")
                    continue
                rest = suffix = None
                for prefix in ("${path.module}", "${path.root}"):
                    if lit is not None and lit.startswith(prefix):
                        suffix = lit[len(prefix):]
                        rest = re.sub(r"\$\{[^}]*\}", "x", suffix)
                if rest is not None and lit.startswith("${path.root}") and rel.startswith("modules/") \
                        and "/examples/" not in rel:
                    out.append(f'{rel}: {fn}("{lit}") reads from path.root in a module: path.root is '
                               "the calling root, which this check does not resolve; use path.module")
                elif rest is None:
                    out.append(f'{rel}: {fn}("{lit}") reads a path that is not under path.module '
                               "or path.root (a file on the runner, such as /proc/self/environ, "
                               "would reach state or outputs)")
                elif posixpath.normpath(posixpath.join(posixpath.dirname(rel), "." + rest)).startswith(".."):
                    out.append(f'{rel}: {fn}("{lit}") reads a path outside the repository')
                elif fn == "templatefile" and "${" not in suffix:
                    out += template_problems(rel, fn, lit, suffix)
                elif "${" in suffix and (why := reader_problems(rel, text, dir_locals, dir_vars)):
                    out += why[1:] if why[0] == "not a reviewed reader" else why
                    out.append(f'{rel}: {fn}("{lit}") builds its path from an interpolation, which '
                               "can hold ../ and leave the repository; use a literal path, or add "
                               "the reviewed reader to FILE_READERS")
            else:
                ref = FILE_ARG_REFERENCE.match(text, at)
                arg = ref.group(0)[:-1].strip() if ref else None
                if ref is None:
                    out.append(f"{rel}: {fn}(...) reads a path built by a function or expression; use a "
                               "literal path under path.module or path.root")
                elif arg not in SAFE_FILE_REFERENCES and (why := reader_problems(rel, text, dir_locals, dir_vars)):
                    out += why[1:] if why[0] == "not a reviewed reader" else why
                    out.append(f"{rel}: {fn}({arg}) reads a path from a reference, whose value this "
                               "check cannot see (file(var.x) with x = /proc/self/environ reads the "
                               "runner's environment); use a literal path under path.module or "
                               "path.root, or pin a reviewed reader in FILE_READERS")
    return out


def override_problems(rel: str, doc: dict) -> list[str]:
    """Override files merge into a module after its other files, so they can
    replace what this check read. Only a fork's backend_override.tf with a
    terraform { backend / cloud } block is allowed, under envs/."""
    name = posixpath.basename(rel)
    if not OVERRIDE_FILE.search(name):
        return []
    if name == BACKEND_OVERRIDE and rel.startswith("envs/") and set(doc) <= {"terraform"} and all(
            set(b) <= {"backend", "cloud"} for b in blocks(doc.get("terraform"))):
        return []
    if name == BACKEND_OVERRIDE:
        return [f"{rel}: backend_override.tf may hold only a terraform {{ backend / cloud }} "
                "block, under envs/"]
    return [f"{rel}: an override file replaces settings of the files this check read; it is "
            "not allowed"]


def check_tfvars(rel: str, doc, pol: dict) -> list[str]:
    """A committed variable file must not set a variable that an allowed
    credential form reads: its value would reach the provider."""
    if not isinstance(doc, dict):
        return [f"{rel}: top level is not an object; fail closed"]
    return [f"{rel}: sets {name}, which an allowed provider credential form reads; set it on "
            "the workspace instead" for name in sorted(set(doc) & pol["credential_vars"])]


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


def is_tfvars(name: str) -> bool:
    return name.endswith(".tfvars") or name.endswith(".tfvars.json")


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
            elif is_tf(path) or is_tfvars(path):
                files.append(path)
        return sorted(files), problems
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        files += [(Path(dirpath) / f).relative_to(ROOT).as_posix() for f in filenames
                  if is_tf(f) or is_tfvars(f)]
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
            doc = parse(ROOT / rel, rel.endswith(".json"))
        except Exception as exc:  # noqa: BLE001 - any parse error fails closed
            problems.append(f"{rel}: cannot parse ({type(exc).__name__}: {str(exc)[:120]}); fail closed")
            continue
        if is_tfvars(rel):
            problems += check_tfvars(rel, doc, pol)
            continue
        if not isinstance(doc, dict):
            problems.append(f"{rel}: top level is not an object; fail closed")
            continue
        docs[rel] = doc

    # required_providers are module-scoped: one map per directory.
    by_dir: dict[str, dict] = {}
    vars_by_dir: dict[str, dict] = {}
    locals_by_dir: dict[str, dict] = {}
    for rel, doc in docs.items():
        by_dir.setdefault(posixpath.dirname(rel), {}).update(required_providers(doc))
        vars_by_dir.setdefault(posixpath.dirname(rel), {}).update(variable_blocks(doc))
        dl = locals_by_dir.setdefault(posixpath.dirname(rel), {})
        for block in blocks(doc.get("locals")):
            for name, value in block.items():
                dl.setdefault(str(name), []).append(value)
    for rel, doc in docs.items():
        d = posixpath.dirname(rel)
        problems += check_doc(rel, doc, by_dir[d], pol, provisioner_dir, vars_by_dir[d], locals_by_dir[d])
    problems += check_chain(docs, pol)

    for p in problems:
        print(f"  ERROR {p}", file=sys.stderr)
    print(f"check-plan-time-exec: {len(docs)} files parsed, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
