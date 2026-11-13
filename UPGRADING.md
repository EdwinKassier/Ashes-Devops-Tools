# Upgrading

How a fork takes a new release of this landing zone, and what to check when it
does. The newest release is first. Every release has one section of manual
steps and one sandbox upgrade log.

## What you own and what upstream owns

A fork keeps upstream's code and adds its own configuration on top. Merges stay
clean when you edit only the files below, which upstream never changes:

| Fork-owned path | Holds |
|---|---|
| `config/*.yaml` (including `config/sandbox/`) | Your landing-zone configuration, TFC workspace overrides and sandbox config. Upstream ships only `*.example.yaml` and fixtures. |
| `.github/CODEOWNERS` | Your review teams. The scaffolder writes it. |
| `envs/**/backend_override.tf` | Your state backend choice for each root (self-managed state). |
| `envs/gcp/guardrails/guardrails.auto.tfvars` | Your GCP IAM deny policies, owned by the security team. |

Everything else (modules, stages, roots, policies, workflows, docs) is
upstream's. If you need to change one of those, send it upstream or carry the
patch knowingly and expect conflicts here.

## Merging a release tag

1. Read the section for each release between your current tag and the new one,
   oldest first. Run every manual step marked as needed before the apply.
2. `git fetch upstream --tags && git merge <tag>`. Conflicts mean a file outside
   the table above was edited in your fork.
3. Regenerate anything your fork pins: `make docs`, and the lockfiles for any
   root you touched (`terraform providers lock -platform=linux_amd64
   -platform=darwin_arm64 -platform=darwin_amd64`).
4. Apply the new tag to your **sandbox** first. The sandbox runs the previous
   release, so the apply is a real N-1 to N upgrade. Fill in the release's
   sandbox upgrade log (template below).
5. Promote layer by layer in apply order. Plans that delete or replace a
   stateful resource stop on `destroy_guard` until the security team overrides
   the run; record every override with its reason in the log.

## Unreleased

Manual steps for the next release, grouped by area. A breaking change
(`feat!:` or a `BREAKING CHANGE` footer) must add its entry here; CI enforces it.

### What your next run does (re-audit 2 code wave)

The 2026-11-13 code wave ([re-audit 2](docs/audit/2026-11-13-due-diligence-reaudit-2.md))
added these entries. Read them before the first run on this release:

- [re-audit-2 SEC-1](#federated-trust-policies-deny-more-forms-policies-breaking-re-audit-2-sec-1):
  with the policy sets on, the guardrails set denies more federated-trust and
  workload identity forms, so a fork's own trust or binding can fail a run.
- [re-audit-2 ADO-20](#a-production-estate-needs-the-policy-sets-or-a-waiver-tfc-admin-breaking-re-audit-2-ado-20):
  the tfc-admin plan fails for a production estate without the policy sets or
  an unexpired waiver. Turning the sets on also changes non-production runs.
- [ARC-H1](#cloud-run-uses-the-egress-proxy-when-it-is-on-gcp-workload-app-services-breaking-arc-h1):
  with the egress proxy on, every Cloud Run service and job gets a new
  revision that sends all traffic through the proxy.
- [ARC-H2](#an-environment-outside-the-hub-region-cannot-use-the-hub-egress-proxy-net-spoke-arc-h2):
  with the egress proxy on, an environment outside the hub proxy region fails
  the plan.
- [ARC-C1](#the-environment-perimeter-now-holds-the-service-team-projects-gcp-workload-breaking-arc-c1):
  an environment perimeter with service teams shows an in-place update; an
  enforced one can block calls to and from the team projects.
- [re-audit-2 SEC-2](#the-organization-plan-identity-loses-rolesloggingviewer-gcp-bootstrap-re-audit-2-sec-2):
  gcp-bootstrap replaces the organization plan identity's `roles/logging.viewer`
  with a custom role.
- [CODEOWNERS](#guardrail-paths-need-a-security-approval-codeowners-cicd-2)
  (re-audit-2 CICD-3): no run changes; copy the extended security-only section
  into your fork's `.github/CODEOWNERS`.

### HCP Terraform and policy

#### Provider credential arguments and ephemeral resources are denied (policies, breaking, re-audit-3 SEC-1 and SEC-2)

**Who:** forks with the policy sets on (`no_plan_time_code_execution` is mandatory) and every fork's CI (`scripts/check-plan-time-exec.py`, run by `make consistency`).
**What changes:** a provider block that sets `profile`, `shared_config_files`, `shared_credentials_files`, `access_key`, `secret_key`, `token`, `access_token`, `api_token`, `assume_role_with_web_identity`, `web_identity_token(_file)`, `impersonate_service_account(_delegates)` or `external_credentials` fails both checks, unless the value is null or every reference is on `allowed_credential_references` in `policies/opa/no_plan_time_code_execution_allowlist.rego`, and a root variable it reads has a null or bool default. An `ephemeral` block whose type is not `tfe_outputs` fails the scanner, and a reference to one fails the policy. Upstream's roots pass unchanged. What can fail in a fork:

- A provider that impersonates a literal service account, as `modules/gcp/network/vpc-sc/examples/basic` and `modules/gcp/stages/workload/examples/basic` did. Use `impersonate_service_account = var.terraform_admin_email` with `default = null` and set the variable on the workspace, as the GCP roots and both examples now do.
- A provider with `profile`, a credentials file or static keys for local runs. Use `AWS_PROFILE` / `AWS_CONFIG_FILE` in your shell or HCP Terraform dynamic credentials instead.
- Your own ephemeral resources (for example `random_password` or `aws_secretsmanager_secret_version`).

**What to do:** remove the argument or the block. If you need another form, add `"<provider type>/<argument>=<var.|local.><name>"` to `allowed_credential_references`, or the type to `allowed_ephemeral_types`, in a reviewed change to the allowlist file (CODEOWNERS: security team), and record why. Both checks read that file.

#### tfc-admin fails when an upstream contract lacks the credential keys

**Who:** forks that set `gcp_bootstrap_outputs_from_tfc` or `aws_organization_outputs_from_tfc` to true.
**What changes:** tfc-admin now fails its plan when the `gcp-bootstrap` outputs lack `tfc_workload_provider_name`, `tfc_plan_service_accounts` or `tfc_apply_service_accounts`, or when the `aws-organization` outputs lack `tfc_plan_role_arns`, `tfc_apply_role_arns` or `tfc_workspace_bindings`. Before, a missing key dropped the `TFC_*` dynamic-credential variables without any error. The error names the missing keys. Apply the upstream workspace first, or fix the renamed output (`scripts/check-contracts.sh`).

#### Every AWS workload needs its own vpc_cidr in the regional pool (tfc-admin)

**Breaking: tfc-admin now fails its plan for configs that passed before.** Spoke VPCs request their `vpc_cidr` from the IPAM pool, so two workloads on the same range collide, and a range outside the home-region pool fails at apply. tfc-admin now fails when:

- two `aws.workload_environments` entries share a `vpc_cidr`, or both omit it (an omitted `vpc_cidr` counts as the built-in `10.72.0.0/16`); or
- a workload `vpc_cidr` is outside `aws.network.regional_cidrs.<org.regions.aws>` (default `10.64.0.0/12`). The static hub ranges (`inspection_cidr`, `egress_cidr`) may sit outside the pool, but they must not overlap any workload or GCP range.

The error names each config key and the two environments. Before you plan tfc-admin:

1. Give each `aws.workload_environments.<env>` its own `vpc_cidr` inside the regional pool, for example `10.72.0.0/16`, `10.73.0.0/16`, and so on.
2. Keep the CIDR of a workload whose VPC already exists. Pick new ranges for the others. Do not move an existing VPC to another range in the same change.
3. Run `terraform plan` in `envs/tfc-admin`. It passes when no two ranges overlap and all sit inside the pool.

#### Production workloads need an approver to apply (tfc-admin)

The platform team no longer has write access on production `gcp-workload-<env>` and `aws-workload-<env>` workspaces. It can queue plans there, but it cannot edit variables or confirm applies. Set `control_plane_approvers_team_id`, or only organization owners can apply production. Production workspaces get the new tag `tier:production`. With `split_workload_projects = true`, a workloads project that holds a production workload becomes custom, and its non-production workloads get write through workspace grants.

#### Workspaces trigger only on the modules their root uses (tfc-admin)

Trigger patterns now list each root's own module trees, not all of `modules/<cloud>/**`. When a root starts to use a new module, add it to `root_trigger_dirs` in `envs/tfc-admin/main.tf`. `scripts/check-consistency.sh` fails until you do. `config/landing-zone.yaml` still triggers every workspace.

#### TFC runs an exact Terraform version (tfc-admin)

`terraform_version` now defaults to `1.17.1`, the version CI tests. Constraints such as `~> 1.17` are rejected. Change it in the same PR as `.tool-versions`.

#### New policies on the TFC layer (tfc-admin, policies)

- `tfc_admin_guard` (mandatory, overridable by the security team) blocks these changes on tfc-admin plans:
  - detaching or weakening a policy set;
  - auto-apply on control-plane or production workspaces;
  - any wider team access or new token.

  Expect a security-team override when you add or remove an environment.
- `tfc_admin_guard` also blocks (breaking: more tfc-admin runs need a security-team override):
  - `execution_mode = local` or `agent`, a repointed agent pool, and any agent pool, agent token or agent pool grant;
  - a changed VCS repository, branch or connection, `working_directory` or `project_id` on a control-plane, bootstrap or production workspace;
  - a new or changed env var named `TFC_*`, `TF_CLI_ARGS*`, `TFE_*`, `TF_TOKEN_*` or one of the code-execution names (`LD_*`, `NODE_OPTIONS`, `GIT_*` and so on), or one with an unknown key or category;
  - attaching a variable set that tfc-admin does not manage to a workspace or project, and making a variable set global.

  Expect an override when tfc-admin pass 2 wires dynamic credentials, when a role or service account behind a `TFC_*` variable changes, and when you set `TF_CLI_ARGS_plan` through `workspace_variables`. Moving `gcp-bootstrap` from `local` to `remote` needs none.
- `tfc_vcs_run_only` (mandatory, overridable by the security team, PREVIEW; breaking: an API-upload apply on a protected workspace now needs a security-team override) blocks a run that can apply on a VCS-connected workspace tagged `layer:control-plane`, `layer:bootstrap` or `tier:production` when the run has no commit SHA. Anyone who applies an API-uploaded configuration version on such a workspace now needs a security-team override. Speculative plans, CLI-driven workspaces and non-production workloads are not affected. Before you rely on it, confirm on a sandbox run that a VCS run carries a non-empty `run.commit_sha` (`docs/known-gaps.md`).
- `no_plan_time_code_execution` (mandatory, not overridable) blocks provisioners outside the reviewed `supabase/vault-secrets` call chain, and the `external` and `http` data sources everywhere. Its later changes are described below.

Both sets now also attach to the tfc-admin workspace itself.

#### Drift detection compares against the applied configuration (CI)

`TFC_TOKEN_DRIFT` now also needs read access to state versions. Drift detection runs a refresh-only plan pinned to the configuration of the last applied run. Changes that are merged but not applied are reported as pending, not as drift.

#### State backup workflow (CI, tfc-admin)

The new `state-backup.yml` exports each workspace's current state daily to a versioned, locked bucket. It fails until it is configured: follow `docs/runbooks/state-backup.md`, or set `STATE_BACKUP_OPT_OUT=true`. tfc-admin's new `state_backup_team_id` grants that team read access to state versions.

#### Dependency update commits use fix(deps) (Renovate, Dependabot)

Renovate and Dependabot now commit as `fix(deps):`, so provider and package bumps appear in the changelog. Each bump now produces a patch release. Dependabot also updates the `pg` package of `vault-secrets`, which is pinned to an exact version.

#### Guardrail paths need a security approval (CODEOWNERS, CICD-2)

**Who:** every fork. Your `.github/CODEOWNERS` is fork-owned, so a merge does not change it.
**What changes:** GitHub uses the last matching CODEOWNERS line, and one approval from any owner on
that line satisfies it. A line that lists the platform and the security team therefore accepts a
platform approval alone. `templates/CODEOWNERS.tftpl` now ends with a section that lists the
security team alone on `/policies/`, `/envs/gcp/guardrails/`, `/modules/gcp/stages/guardrails/`,
`/scripts/check-plan-time-exec.py`, `/.github/requirements/`, `/.github/CODEOWNERS`,
`/templates/aws/bootstrap/` and `/templates/CODEOWNERS.tftpl`, so a change there needs a security
approval. The section now also lists `/modules/gcp/iam/deny-policy/` (the module behind the org
IAM deny policies), `/modules/tfc/` (the workspace module tfc-admin uses), `/renovate.json`,
`/release-please-config.json`, `/.tool-versions` and `/.pre-commit-config.yaml` (re-audit-2 CICD-3). Before,
`/modules/gcp/iam/` and `/.pre-commit-config.yaml` accepted a platform approval alone, and the
other four fell to the platform-only default. Copy that section ("Guardrails (security team ONLY ...)") to the end of your
`.github/CODEOWNERS` and replace `${security_team}` with your security team. Delete the old `/modules/tfc/` and
`/.pre-commit-config.yaml` lines from the upper sections when you copy the new ones. Do not re-run the
scaffolder over an existing `config/landing-zone.yaml`: its `--force` overwrites that file too. Keep
the section last, or a broader line after it wins. It takes effect only when code-owner review is required on the default
branch ([branch protection](docs/guides/BRANCH_PROTECTION.md)).

#### Platform team cannot queue plans where static secrets live; one SaaS reader team per stack (tfc-admin)

**Breaking.** A plan runs code with the workspace's environment variables, and
anyone with `plan` permission can run a CLI speculative plan of their own,
unreviewed configuration (`speculative_enabled = false` stops only automatic PR
plans). So:

- On the self-managed `platform` project (tfc-admin, which holds `TFE_TOKEN`)
  and the `saas` project (account-wide Supabase/Vercel tokens), the platform team
  now gets custom `runs = read` instead of `plan` (tfc-admin) or fixed `write`
  (saas). The approvers team (`control_plane_approvers_team_id`) now confirms
  `saas-*` runs. Without an approvers team, only organization owners can run
  `saas-*`: set one before the upgrade apply.
- `saas_outputs_reader_team_id` is removed (the plan fails while it is set).
  Create one reader team per `saas-<name>` workspace and set
  `saas_outputs_reader_team_ids = { "saas-<name>" = "team-..." }`. Then create
  a token for each team and replace the `TFE_TOKEN` on each bridging workload
  with the token of the stack it bridges
  ([saas-bootstrap](docs/runbooks/saas-bootstrap.md#bridging-secrets-to-a-workload-and-rotating-them)).
  Delete the old shared team's token afterwards.

Also in this change (no manual step): `scripts/check-consistency.sh` (CI) fails
on a `data "external"`, `data "http"`, provisioner or `hashicorp/external` /
`hashicorp/http` provider outside the reviewed allowlist.

#### saas state access (tfc-admin)

**Breaking.** `saas-*` state holds the Supabase database password and
service-role key, and HCP Terraform's fixed `read` includes the full state file.

- `viewer_team_ids` keep fixed `read` on every other project. On the saas
  project they now get custom access: runs and variables read, `state_versions =
  none`. They can no longer download saas state or read its outputs.
- The state-backup team (`state_backup_team_id`) loses the saas project unless
  `enable_saas_state_backup = true`. Remove `saas-*` from the
  `STATE_BACKUP_WORKSPACES` repository variable, or the backup job fails on
  them. HCP Terraform keeps every saas state version.
- The platform team (`platform_team_id`) loses `state_versions = read-outputs`
  on the saas project (now `none`; runs and variables stay read). Its members
  can no longer see saas outputs in the UI or through the API. Read-outputs
  still let the API return a sensitive output value. Bridging workloads are not
  affected: they read the saas outputs with their saas-outputs-reader team
  token. A person who needs a saas output asks an organization owner or the
  team that confirms saas applies.
- Optional: set `saas_approvers_team_id` to a small, dedicated team. It then
  confirms `saas-*` applies instead of `control_plane_approvers_team_id`. A
  team that may confirm an apply may also queue a plan, and a plan can read
  `SUPABASE_ACCESS_TOKEN` and `VERCEL_API_TOKEN`. While it is unset, the check
  `saas_approvers_dedicated` warns on every plan.

#### Secret-bearing workspaces are derived from their variables (tfc-admin)

**Breaking.** Before, only the tfc-admin and `saas` projects were
secret-bearing. Now tfc-admin also marks every workspace that it writes a
sensitive variable to, that has a variable whose key looks like a secret
(`*_TOKEN`, `*_SECRET`, `*_SECRET_KEY`, `*_SERVICE_ROLE_KEY`, `*_PASSWORD`,
`*_PASSWD`, `*_PASSPHRASE`, `*_PRIVATE_KEY`, `*_API_KEY`, `*_ACCESS_KEY`,
`*_CREDENTIALS`), or that sets `enable_saas_secret_bridge` to any value other
than an explicit false (`false`, `0` or empty)
(in `workspace_variables`, the committed `workspace_variables_file`, or as
`TF_VAR_enable_saas_secret_bridge`). This includes non-production workloads.
A sensitive or secret-named value in `common_workspace_variables` marks every
workspace except gcp-guardrails. Who loses what:

- **Platform team** (`platform_team_id`): on every project that holds a
  secret-bearing workspace it now gets custom `runs = read` (no plans, no
  applies, variables read-only). Before, it had
  `platform_team_control_plane_runs` (default `plan`) on production workload
  and control-plane projects and fixed `write` on non-production workload
  projects. A secret-bearing non-production workload also loses its
  workspace-level `write` grant. Other non-production workloads keep `write`.
  In a split workloads project that held only non-production workloads, they
  move from the project-level `write` grant to a new workspace-level `write`
  grant. `tfc_admin_guard` stops that create too; the same security-team
  override covers it.
- **Pull requests:** secret-bearing workspaces no longer run speculative plans.
- **One project per cloud** (`split_workload_projects = false`): a
  secret-bearing workload shares the `<prefix>gcp` / `<prefix>aws` project with
  the control plane, so the platform team also drops to `runs = read` on the
  control plane. A `check` warns.

The approvers team (`control_plane_approvers_team_id`) gets `runs = apply` on
every secret-bearing project (except the tfc-admin project). Before, a
non-production bridging workload was applied by the platform team. **Set an
approvers team before the upgrade apply**, or only organization owners can run
those workloads. With the policy sets attached, `tfc_admin_guard` stops the
upgrade apply because it creates new approvers grants: the security team
overrides that run.

To restore access:

- Set `split_workload_projects = true` first, so that only the workloads
  project drops to `runs = read` (AWS: the workload accounts' OIDC trust must
  name the workloads project before you enable it; see the variable
  description).
- Opt back into speculative plans with `enable_speculative_on_secret_bearing = true`.
  The platform team stays at `runs = read`: there is no opt-out for that,
  because any plan can read the secret.
- Move a secret out of `common_workspace_variables` onto the workspaces that
  need it (`workspace_variables`).

#### `no_plan_time_code_execution` is exact and checks providers (policies)

**Breaking.** The policy is mandatory and not overridable (`policy_set_overridable = false`),
and the policy set is read from your VCS branch. After you merge this change,
the next run of each workspace uses it. The unchanged upstream roots pass:
every provider they declare is on the list, no root provider block sets an
endpoint key, every remote-state read uses `backend = "cloud"`, and
`envs/saas` keeps the reviewed module chain. The allowlists are in
`policies/opa/no_plan_time_code_execution_allowlist.rego`: a fork edits only
that file, in a reviewed change. A run is now denied after its plan in these
cases:

- **A provisioner outside the exact chain.** Only resources declared directly
  in `module.saas_workload.module.vault_secrets`, called with the sources
  `../../modules/saas/stages/saas-workload` and
  `../../../supabase/vault-secrets`, may declare a provisioner. Before, any
  module source that ended in `supabase/vault-secrets` passed. If your fork
  calls `vault-secrets` from another root, renames either module call, or
  moves either directory, restore the upstream layout.
- **A provider that is not on the list.** The list is `hashicorp/archive`,
  `aws`, `azurerm`, `google`, `google-beta`, `null`, `random`, `tfe`,
  `supabase/supabase`, `vercel/vercel` and the built-in `terraform`, all from
  `registry.terraform.io`. A provider from a private registry or another
  namespace is denied, also when its type name is `aws` or `google`. If your
  fork uses another provider, add its full source address to
  `allowed_provider_sources` in the allowlist file.
- **A provider endpoint, proxy or TLS override.** Any provider block that sets
  `endpoints`, a key that ends in `_endpoint` (except `use_fips_endpoint`,
  `use_dualstack_endpoint` and `s3_us_east_1_regional_endpoint`), `hostname`, `base_url`, `api_url`,
  `metadata_host`, `universe_domain`, `custom_ca_bundle`, `insecure`,
  `ssl_skip_verify`, `skip_tls_verify`, `http_proxy`, `https_proxy` or
  `no_proxy` is denied, whatever the value. Examples: a LocalStack `endpoints`
  block, a corporate proxy, or `hostname` on the `tfe` provider for Terraform
  Enterprise. Remove the key. A switch or enum that takes no host name goes
  in `endpoint_key_exceptions` in the allowlist file. To allow a real
  override, change `endpoint_key_pattern` in the policy in a reviewed change,
  and record why.
- **A remote-state read with another backend.** A
  `data "terraform_remote_state"` whose `backend` is not the literal `cloud`
  or `remote` is denied, also when `backend` is a variable or local. Use the
  `cloud` backend, or add the backend to `allowed_remote_state_backends` in
  the allowlist file.
- **A Lambda invocation or an action block.** `data "aws_lambda_invocation"`
  invokes a Lambda function during the plan and is denied like `external` and
  `http`. An `action` block (Terraform 1.14 and later, for example
  `aws_lambda_invoke`) runs provider code at apply time and is denied unless
  its type is on `allowed_action_types` in the allowlist file, which is empty.
- **Inline provider credentials.** A provider block that sets `credentials` or
  `token_url` is denied. Use the workspace's dynamic credentials instead.

The plan of a denied run has already run, so a denial is not a rollback. To
unblock a run that you judge safe before the policy change merges, set
`policy_set_overridable = true` in tfc-admin as a time-boxed break-glass
(`tfc_admin_guard` stops that tfc-admin plan until the security team
overrides it), or ask an organization owner to detach the policy set in the
HCP Terraform UI. Revert either one when the run is done.

#### The plan-time execution gate parses HCL and checks module sources (CI)

**Breaking for some forks.** `scripts/check-consistency.sh` (`make consistency`,
`make ci` and CI meta-lint) now runs `scripts/check-plan-time-exec.py`, which
parses every `.tf` and `.tf.json` file in the repository. The unchanged upstream
tree passes. Before you merge:

- **Install `python-hcl2` for local runs.** `make consistency` fails (exit 2
  from the checker) without it:
  `python3 -m pip install --user --no-deps --require-hashes -r .github/requirements/hcl2.txt`
  (inside a virtualenv if your Python is externally managed). `make install`
  does this. CI installs it in the meta-lint job.
- **Module sources must be local or this repository's release tag.** A
  `module` whose `source` is a registry address, another Git URL or an
  unpinned ref now fails the check. Vendor the module under `modules/`, or add
  a pattern for your own release URL next to `OWN_RELEASE_MODULE` in the
  script in a reviewed change.
- **Same lists as the OPA policy, now before the merge.** A provider that is
  not on `allowed_provider_sources`, a provider endpoint, proxy or TLS key
  (including inside a `dynamic` block), a `terraform_remote_state` backend
  other than `cloud` or `remote`, and a `data "external"` / `data "http"`
  block fail the check. The script reads these lists from
  `policies/opa/no_plan_time_code_execution*.rego`, so a fork that extends
  the allowlist file extends both controls.
- **Provisioners.** They are allowed only in the module that the policy's
  `allowed_provisioner_chain` reaches from `envs/saas`
  (`modules/supabase/vault-secrets`) and in
  `terraform_data.archive_settle` of `tests/e2e/aws/main.tf`. A provisioner in
  a `removed` block always fails. If you rename a call in that chain, update
  the policy in the same change: the check fails when the chain in the policy
  and the module calls in `envs/saas` and `modules/saas/stages/saas-workload`
  differ.
- **Every file must parse, with no fallback.** python-hcl2 7.3.1 rejects one
  valid HCL form: a line inside parentheses that starts with `?`, `:`, `&&` or
  `||`. Such a file fails the check. Put the operator at the end of the line
  before (`cond ?` then `a :` then `b`). A `.tf.json` file with a duplicate
  key at any level fails too.
- **Tracked files only.** The check reads `git ls-files`. A tracked symlink, a
  submodule, or a tracked file under `.terraform/` or `node_modules/` fails,
  and so does a local module source that points into `.terraform/` or
  `node_modules/`.
- **The policy lists must be plain literals.** Each list in
  `policies/opa/no_plan_time_code_execution*.rego` that the script reads must
  be a set (or array) of string literals, defined once in the package. A
  comprehension, a set expression or a second definition makes the script
  exit 2.

#### The committed workspace file cannot set redirection env vars (tfc-admin)

**Breaking for some forks.** `workspace_variables_file`
(`config/tfc-workspaces.yaml`) already could not set `TFC_*`, `TF_CLI_ARGS*`
or provider-auth env vars. It now also rejects these env-category keys:
`TFE_*`, `TF_TOKEN_*`, `TF_CLI_CONFIG_FILE`, `HTTP_PROXY`, `HTTPS_PROXY`,
`ALL_PROXY` and `NO_PROXY` (in any case), `SSL_CERT_FILE` and `SSL_CERT_DIR`.
Each one can send a workspace's tokens to another host or make it trust
another certificate authority. The tfc-admin plan fails and names the keys.
Remove them from the file. If a workspace really needs one (a corporate
proxy, for example), set it through `workspace_variables` in tfc-admin, which
the tfc-admin owners review.

#### Env vars that run other code are refused (tfc-admin, breaking)

**Breaking if you set one of these.** The tfc-admin plan now fails, and names
the keys, when an env-category variable in `workspace_variables` or in
`workspace_variables_file` is one of: `TERRAFORM_CONFIG`,
`TF_CLI_CONFIG_FILE`, `LD_*`, `DYLD_*`, `NODE_OPTIONS`, `NODE_PATH`, `GIT_*`,
`BASH_ENV`, `BASH_FUNC_*`, `ENV`, `SHELLOPTS`, `PS4`, `PYTHON*`, `PERL5OPT`,
`PERL5LIB`, `RUBYOPT`, `RUBYLIB`, `JAVA_TOOL_OPTIONS`, `_JAVA_OPTIONS`,
`GCONV_PATH`, `SSH_ASKPASS*` or `PATH`. Each one makes the run load or start
code that is not in the reviewed configuration. Before, `workspace_variables`
accepted all of them, and the committed file accepted all but
`TF_CLI_CONFIG_FILE`. The committed file now also rejects
`NODE_EXTRA_CA_CERTS`, like `SSL_CERT_FILE`. Remove the keys before you
upgrade. A corporate CA bundle or proxy still goes through
`workspace_variables`. Private module downloads that need git credentials
belong in the HCP Terraform VCS connection or an agent host, not in a
workspace variable.

#### Run triggers auto-apply explicitly non-prod workloads (tfc-admin)

**Trust change on the upgrade apply (estates with policy sets on).** tfc-admin's
new `enable_nonprod_workload_auto_apply` defaults to `null`, which follows the
policy sets: it is on only while `enable_policy_sets` is on, so the mandatory
`destroy_guard` (below) is attached to every auto-applied run. An estate without
policy sets (no `org.tfc.plan`, or a free/essentials plan) keeps manual
confirmation and sees no change. With policy sets on, every
`gcp-workload-<env>` / `aws-workload-<env>` whose environment sets
`is_production: false` **explicitly** gets `auto_apply_run_trigger` and
`queue_all_runs`. A confirmed upstream apply (`gcp-network-hub`, `aws-network`,
`aws-security`) then applies those workloads with no second confirmation.
Production workloads and every shared workspace are unchanged. An environment
without the flag used to keep manual confirmation; every environment must now
set `is_production` (see "`is_production` is required on every environment"
below), so `is_production: false` on a former unflagged environment turns
auto-apply on for it. Set `is_production: true` where you want to confirm by hand.

**To keep the previous behaviour,** set `enable_nonprod_workload_auto_apply = false`
on tfc-admin **before** the upgrade apply.
`enable_nonprod_workload_auto_apply = true` forces auto-apply on without policy
sets; do that only if you accept non-prod applies with no destroy guard.

Also in this release (no manual step):

- tfc-admin rejects `config/tfc-workspaces.yaml` entries on a security-only
  workspace (`gcp-guardrails`): the file is platform-editable, so the plan fails
  naming the entry. The only allowed entry is `landing_zone_config_path` set to
  this estate's own landing-zone file (as `config/sandbox/tfc-workspaces.yaml`
  does). Move any other value into `envs/gcp/guardrails` (security-owned) or the
  security team's `workspace_variables`. CODEOWNERS now also lists the
  security team on `config/tfc-workspaces.yaml` and
  `modules/aws/stages/{organization,security,backup}/`, beside the platform
  team, so either team's approval satisfies those lines; copy them from
  `templates/CODEOWNERS.tftpl` into a CODEOWNERS you scaffolded earlier.
- tfc-admin now triggers `aws-organization` after each of its applies. It
  triggers `gcp-bootstrap` too once that runs remotely
  (`workspace_execution_modes = {}`). Plans with no changes end as "planned and
  finished".
- With `gcp_bootstrap_outputs_from_tfc`, tfc-admin derives each
  `gcp-workload-<env>`'s SA emails from `org.prefix` (or `gcp_project_prefix`)
  and the gcp-bootstrap `admin_project_id` output. A `check` warns when a
  derived email disagrees with a gcp-bootstrap output; align `org.prefix` with
  gcp-bootstrap's `project_prefix`. The plan fails on an invalid prefix or on
  `<prefix>-wl-<env>-apply` over 30 characters.
- A `check` warns while `gcp_bootstrap_outputs_from_tfc` is on and
  `gcp-bootstrap` still runs locally.

#### The destroy guard is mandatory, in its own overridable policy set

`destroy_guard` moves from `policies/opa/` (advisory) to
`policies/opa-destructive/` (mandatory), and tfc-admin attaches it as a second
set, `<project_name_prefix>destructive-change-guard`, with `overridable = true`.
It now denies every delete or replace of a stateful type (databases, buckets,
KMS keys, projects/folders/accounts, networks, secrets, log sinks/buckets,
CloudTrail, StackSet instances, `supabase_project`, and the admin-containment
deny policies with their `google_tags_tag_key` / `google_tags_tag_value`), not
only log-named buckets. The `<prefix>opa-guardrails` set stays non-overridable.

**Manual steps (estates with policy sets on):**

1. An organization owner creates a `security` team in HCP Terraform (if it does
   not exist), grants it **Manage Policy Overrides** in the organization
   settings, and sets its ID as tfc-admin `security_team_id`. Without it only
   owners can override an intended destroy (a check warns).
2. Set `org.tfc.plan` in `config/landing-zone.yaml` (`free | essentials |
   standard | premium`). `enable_policy_sets` now defaults to null: on with
   `vcs_repo` and a `standard` or `premium` plan. An explicit
   `enable_policy_sets` still wins. Without `org.tfc.plan` the sets stay off,
   as before, and a `destructive_changes_guarded` check warns.
3. Expect plans that delete or replace a stateful resource to stop on
   `destroy_guard` until the security team overrides the run.

`drift-detection.yml` now fails a leg whose workspace does not exist instead of
skipping it. A single-cloud estate sets the `TFC_DRIFT_WORKSPACES` repository
variable to its own workspaces (or `REAL_CLOUD_CHECKS_OPT_OUT=true`).

#### destroy_guard covers backups, registries and DNS zones (policies, breaking)

**Breaking: runs that passed before now stop until the security team
overrides them.** `destroy_guard` (in the overridable
`<prefix>destructive-change-guard` set) now also denies a delete or replace
of `aws_backup_vault`, `aws_backup_vault_lock_configuration`,
`aws_s3_bucket_object_lock_configuration`, `aws_efs_file_system`,
`google_bigquery_dataset`, `aws_ecr_repository`,
`google_artifact_registry_repository`, `aws_route53_zone` and
`google_dns_managed_zone`. A teardown, a removed environment or service, or a
change that forces a replace (for example a new `bigquery_location` on a flow-log
dataset, or a renamed DNS zone) now needs a security-team override on the
run, as the [teardown runbook](docs/runbooks/teardown.md) describes. No
manual step is needed before the upgrade.

#### destroy_guard covers clusters and backup plans, and deletion protection turned off (policies, breaking)

**Breaking: runs that passed before now stop until the security team
overrides them.** `destroy_guard` (in the overridable
`<prefix>destructive-change-guard` set) now also denies:

- a delete or replace of `google_container_cluster`, `google_spanner_instance`,
  `google_spanner_database`, `google_bigtable_instance`,
  `google_filestore_instance`, `google_sql_database`, `aws_rds_global_cluster`,
  `aws_elasticache_replication_group`, `aws_elasticache_cluster`,
  `aws_backup_plan` and `aws_backup_selection`;
- an in-place update, on any resource type, that turns a deletion-protection
  switch off: `deletion_protection`, `deletion_protection_enabled`,
  `enable_deletion_protection`, `delete_protection`,
  `termination_protection_enabled` or `enable_drop_protection` from `true`
  to `false`, null or an unknown value; `deletion_policy` away from
  `"PREVENT"`; and the string switches of `aws_cognito_user_pool`,
  `google_bigtable_table` and `google_firestore_database`.

`aws_backup_selection` has no in-place update: every change to a selection
(its resources, conditions or IAM role) is a replace, so every such run needs
an override.

In this repository that includes setting `enable_deletion_protection` to
`false` on an existing GKE Autopilot cluster, Cloud SQL instance, Cloud Run
service or job, Private CA certificate authority, Aurora cluster, load
balancer or Network Firewall, and changing a
project's `deletion_policy` from `"PREVENT"` before a teardown. Each such run needs a security-team override, as the
[teardown runbook](docs/runbooks/teardown.md) describes. No manual step is
needed before the upgrade.

#### tfc_admin_guard checks where an unknown variable set ID comes from (policies, breaking)

**Breaking: a run that passed before can now stop until the security team
overrides it.** A `tfe_workspace_variable_set` or `tfe_project_variable_set`
whose `variable_set_id` is unknown at plan time used to pass whenever the
same plan created any `tfe_variable_set`. Now its configuration must
reference a `tfe_variable_set` resource, directly or through `each.value`,
module arguments and module `for_each`. tfc-admin's own attachments
(`module.workspace` with `variable_set_ids = { common = tfe_variable_set.common.id }`)
pass. A fork that passes a new set's ID through a `local`, a data source or a
module output is denied on the plan that creates the set: pass the resource reference
directly, or have the security team override that one run.

#### Mandatory OPA controls deny unknown values (policies, breaking)

**Breaking: the non-overridable guardrails set now fails runs that passed
before.** These mandatory rules used to skip a value that is unknown at plan
time. They now deny it:

| Policy | Attributes |
|---|---|
| `gcs_no_public_buckets` | `google_storage_bucket` `uniform_bucket_level_access`, `public_access_prevention` |
| `aws_s3_public_access` | `block_public_acls`, `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` on `aws_s3_bucket_public_access_block` and `aws_s3_account_public_access_block` |
| `aws_kms_key_rotation` | symmetric `aws_kms_key` `enable_key_rotation` |
| `database_private_encrypted` | `aws_db_instance` / `aws_rds_cluster` `storage_encrypted`; `aws_db_instance` / `aws_rds_cluster_instance` `publicly_accessible` |

Every module in this repo sets these attributes to literals. A fork fails when
it sets one from an apply-time value, or omits an attribute that the provider
computes when it is not set (for example `public_access_prevention` and
`uniform_bucket_level_access` on a new bucket, `storage_encrypted` on a new
Aurora cluster, `publicly_accessible` on a new cluster instance). Set each one
explicitly to a plan-known value. The message ends with "an unknown value
counts as a violation".

#### Federated-trust policies deny more forms (policies, breaking, re-audit-2 SEC-1)

**Breaking: the non-overridable guardrails set now fails runs that passed
before.** No trust or binding that this repo builds is denied. A fork's own
code, or an app-services `github.subject` from a customised claim template,
can be.

`aws_iam_federated_trust_pinned` (every `aws_iam_role` that allows web
identity) now denies:

- a subject or an audience that holds `*` or `?`, under any operator, for
  example `organization:acme:project:p:workspace:*:run_phase:plan`;
- a statement whose only `:sub` or `:aud` conditions are under
  `ForAllValues:` operators, or under keys that do not name one of the
  statement's Federated providers (keys are compared without case);
- a web-identity action on any principal (`"*"` or `{"AWS": "*"}`);
- a TFC subject that is not the full
  `organization:<org>:project:<project>:workspace:<ws>:run_phase:<plan|apply>`;
- a GitHub subject without a literal repository (`repo:<owner>/<repo>:` or
  `repository_id:<id>`) and a `ref:` or `environment:` value, for example
  `repo:acme/app:pull_request` or a template that holds only
  `job_workflow_ref`;
- a trust that is unknown at plan time, unless the role itself is created in
  that run and the same run creates an `aws_iam_openid_connect_provider` or an
  `aws_organizations_organization` in the role's module instance or in a
  module below it. An update of an existing role is never exempt. So turning
  `create_github_oidc_provider` on for an app-services deploy role that
  already exists needs two runs: first a run that targets only
  `module.app_services.aws_iam_openid_connect_provider.github`, then the
  normal run, in which the provider ARN is known;
- a statement that allows web identity with `NotPrincipal`, or to
  `{"Federated": "*"}`.

The app-services stage also fails the plan for a `github.subject` without a
literal repository and a `ref:` or `environment:` value.

It also treats `sts:AssumeRoleWith*`, `sts:*`, other letter case and a
`NotAction` that does not exclude `sts:AssumeRoleWithWebIdentity` as web
identity, so those statements are now checked.

`gcp_wif_principalset_pinned` now also denies the workload identity members
`attribute.terraform_*/...` (raw TFC claims), `attribute.repository_owner/...`,
`attribute.actor/...` and `attribute.aud/...`, and any workforce pool member
(`principal://` or `principalSet://iam.googleapis.com/locations/global/workforcePools/...`)
on `roles/iam.workloadIdentityUser`, `roles/iam.serviceAccountTokenCreator`,
`roles/iam.serviceAccountOpenIdTokenCreator`, `roles/iam.serviceAccountKeyAdmin`,
a custom role or a role unknown at plan time. It denies
`attribute.account/...`, `attribute.repo_env/<id>/-` and any member that holds
`*` or `?` (other than the whole-pool `/*`, which was already denied) on any
role. On every role, a workload pool member must be
`attribute.repo_ref/`, `attribute.repo_env/`, `attribute.repo_ref_env/`,
`attribute.workspace_id_phase/` or `attribute.workspace_phase/`;
`attribute.repository_id/` and `attribute.project_path/` pass with an
advisory, and any other form (for example `attribute.role/...`,
`attribute.namespace_path/...`, a GKE `namespace/...` set or a `group/...`) is
denied, also on resource roles such as `roles/storage.objectViewer`. The
scheme, host and pool path of a member are matched without case. A
`principal://.../workloadIdentityPools/<pool>/subject/<sub>` member is denied
when `<sub>` is a TFC or GitHub subject that the AWS rules above deny.

Before the upgrade:

1. Search your plans and code for the forms above.
2. Pin each TFC subject to one workspace and one run phase. On GCP, bind
   `attribute.workspace_id_phase/<ws-id>:<phase>` (gcp-bootstrap does this).
3. Make each GitHub subject name the repository and a ref or an environment.
   For a customised claim template, include `repo` or `repository_id` and
   `context` (or `environment` or `ref`).
4. Build each trust from values known at plan time. When a trust names a role
   or account that the same run creates (and no OIDC provider or organization
   is created in that run), apply the referenced resource in an earlier run.
5. Grant workforce identities direct roles, not service account
   impersonation.
6. On GCP, grant a pinned principalSet, or a single `principal://` subject
   that names one workspace and run phase or one repository and ref or
   environment, to each role that acts as a service account.

#### Wildcard workload identity bindings are denied (policies, breaking)

**Breaking: the non-overridable guardrails set now fails runs that passed
before.** The new mandatory policy `gcp_wif_principalset_pinned` denies a
workload identity member
`principalSet://iam.googleapis.com/projects/<n>/locations/global/workloadIdentityPools/<pool>/<suffix>`
when `<suffix>` is `*`, `attribute.repository_owner_id/...`,
`attribute.repository/...` or `attribute.ref/...`. It checks every
`google_*_iam_member`, `google_*_iam_binding` and `google_*_iam_policy`, for
any role. No root in this repo emits one of these members. A fork can emit
one, for example:

- through `modules/gcp/iam/workload-identity` with a `github_sa_bindings`
  entry that has no `repository_id` and an empty `github_allowed_refs` (the
  member is `attribute.repository/<owner>/<repo>`);
- through `modules/gcp/iam/service-account` `workload_identity_members`, or a
  hand-written IAM resource.

Before the upgrade, search your plans or code for those member forms. Bind
`attribute.repo_ref/<repository_id>/<ref>`, `attribute.repo_env/<repository_id>/<environment>`
or `attribute.repo_ref_env/<repository_id>/<ref>/<environment>` instead. For
the workload-identity module, set `repository_id` and `github_allowed_refs`.
A member bound on `attribute.repository_id/<id>` alone, or a member that is
unknown at plan time, is reported by the advisory
`gcp_wif_principalset_repo_wide` and does not block the run.

#### A production estate needs the policy sets or a waiver (tfc-admin, breaking, re-audit-2 ADO-20)

**Who:** forks with a production environment (`is_production: true` in
`gcp.environments` or `aws.workload_environments`, for a cloud that is enabled)
whose OPA policy sets are off: no `org.tfc.vcs_repo`, `org.tfc.plan` unset,
`free` or `essentials`, or `enable_policy_sets = false`.
**What changes:** **Breaking.** tfc-admin now fails its plan
(`terraform_data.policy_sets_guard`). Before, the `destructive_changes_guarded`
check only warned, so production ran with no `destroy_guard`,
`tfc_admin_guard` or guardrail policy. The error names the production
workspaces and why the sets are off. Estates on `standard` or `premium` with
`vcs_repo` set see no change.

Before you plan tfc-admin, do one of these:

1. Set `org.tfc.plan: standard` (or `premium`) and `org.tfc.vcs_repo` in
   `config/landing-zone.yaml`. This creates both policy sets. Set
   `security_team_id` too, or only organization owners can override the
   destructive-change guard.

   On an estate that had the policy sets off, this changes every managed
   workspace's next run, not only production. The `<prefix>opa-guardrails`
   set applies all 13 mandatory policies in `policies/opa`, and no one can
   override them (`policy_set_overridable` defaults to false). They include
   the stricter federated-trust and workload identity rules above
   (re-audit-2 SEC-1). `enable_nonprod_workload_auto_apply` defaults to
   `enable_policy_sets` (`envs/tfc-admin/main.tf`), so every workload whose
   environment sets `is_production: false` gets `queue_all_runs` and
   auto-apply on run triggers
   ([Run triggers auto-apply explicitly non-prod workloads](#run-triggers-auto-apply-explicitly-non-prod-workloads-tfc-admin)).
   The `<prefix>destructive-change-guard` set starts `destroy_guard`,
   `tfc_admin_guard` and `tfc_vcs_run_only` (PREVIEW), so a stateful delete
   or replace, a weakening tfc-admin change and an API-uploaded apply on a
   control-plane or production workspace need a security-team override.
   Before you turn the sets on, run `make opa-test`, and run each
   workspace's current plan through `opa eval` against `policies/opa` and
   `policies/opa-destructive`
   ([how](docs/architecture/policy-as-code.md)). To keep today's
   confirmation behaviour, set `enable_nonprod_workload_auto_apply = false`
   on tfc-admin in the same change.
2. On a plan without VCS policy sets, record the risk with a time-boxed waiver:

   ```yaml
   org:
     tfc:
       policy_sets_waiver:
         reason: essentials plan until the Standard upgrade
         expires: "2027-03-31"   # last day it waives (UTC), quoted
   ```

   After `expires` the plan fails again. A waiver with an empty reason or a
   date that does not exist also fails the plan.

New scaffolds: `scripts/init-landing-zone.sh --tfc-plan` writes `org.tfc.plan`
(`standard` by default with `--profile production`).

### AWS

#### Production hub network alarms need a subscriber (aws-network)

**Breaking: a production aws-network plan now fails without an alarm contact.** The hub creates CloudWatch alarms for transit gateway blackhole drops, NAT gateway port allocation errors and, with the VPN, VPN tunnel state. They publish to an SNS topic in the network account. A topic with no subscriber notifies nobody, so the root fails a production plan (`org.profile: production`, or any `aws.workload_environments` entry with `is_production: true`) unless there is a real contact. Before you plan `aws-network`, do one of these:

1. Set `notifications.emails` in `config/landing-zone.yaml`. The `aws-security` root already needs it in production, so most forks have it.
2. Set `alarm_subscriber_emails` on the root.
3. Set `alarm_sns_topic_arn` to a topic you own that allows `cloudwatch.amazonaws.com` to publish.

Example, `.invalid`, `.localhost` and `.test` addresses are rejected. Each address receives a confirmation email; the subscription does nothing until it is confirmed. A starter estate without production workloads is not blocked. The apply adds the topic, one alarm per NAT gateway, one for the transit gateway and, with `enable_vpn`, one for the VPN. The `aws-network-hub` stage has two new inputs (`alarm_sns_topic_arn`, `alarm_subscriber_emails`, both optional) and three new outputs (`alarm_topic_arn`, `network_alarm_arns`, `network_alarms`).

#### Developer is refused in production accounts (CMP-14, aws-identity, breaking)

**Breaking: the `aws-identity` plan now fails for configs that passed before.** A new plan guard (`terraform_data.production_assignment_guard`) refuses an assignment of any set in `production_restricted_permission_sets` (default `["Developer"]`, which is PowerUserAccess) in a production workload account. A production account is the `account_key` of an `aws.workload_environments` entry with `is_production: true`, or the list in `production_account_keys`. The check covers `aws.identity.groups`, `identity_groups` and `assignments` (by `account_key` or `account_id`). The error names each assignment key. Before you plan `aws-identity`:

1. Find the assignments the error names. Move those groups to a read-only or scoped set (for example `ReadOnly`) in the production account.
2. For time-boxed write access, use identity-provider access requests on a group bound to a scoped set ([ADR 0011](docs/adr/0011-temporary-elevated-access.md)), not a standing `Developer` assignment.
3. Only if you must keep the assignment, set `production_restricted_permission_sets = []` (or a shorter list) and record the reason next to it. The first apply also creates the guard's `terraform_data` resource; it holds no cloud object.

#### No placeholder SecOps subscriber (CMP-6, aws-security, breaking)

`aws-security` no longer subscribes `secops@example.com` to the security-notifications topic (GuardDuty, Security Hub, root use, console sign-in without MFA, break-glass use) and, unless `cloudtrail_alarm_subscribers` is set, to the CIS alarm topic. That address never delivered.

- **Production fails the plan** until a real subscriber is set. Production means `org.profile = production` (the default), or any `aws.workload_environments` entry with `is_production: true`. Set `notifications.emails` in `config/landing-zone.yaml`, or `aws_overrides.notification_subscribers`. A subscriber on `example.com`, `example.net`, `example.org` (or a subdomain), or on a `.example`, `.invalid`, `.localhost` or `.test` domain also fails the plan.
- **Non-production** (`org.profile = starter` and no production workload environment) plans with no subscriber and shows a warning (`check.security_contact_set`).

What you see on apply: the old `secops` subscription is destroyed (with `notifications.emails` set, the new subscriptions are created; each email recipient must confirm). The stage default for `aws.notification_subscribers` is now `{}`, and the stage and `security-notifications` module accept an empty map.

#### Patch Manager now installs patches (CMP-3, systems-manager, aws-security, aws-workload, breaking)

`modules/aws/ops/systems-manager` adds two `AWS-RunPatchBaseline` State Manager associations in every account that runs it: the security-tooling account (aws-security) and each workload account (aws-workload, `enable_ssm` default `true`). Each association is regional: it covers the provider region of that root.

- `<patch_baseline_name>-scan`: a daily `Scan`. It reports patch compliance and never reboots.
- `<patch_baseline_name>-install`: a weekly `Install` with `RebootOption = RebootIfNeeded`, Sunday 03:00 UTC, 10% concurrency, 10% error threshold. **Instances reboot when a patch needs it.**

Which instances: every SSM-managed instance in that account and region. That is an EC2 instance or hybrid node that runs the SSM Agent and is registered with Systems Manager (an instance profile with `AmazonSSMManagedInstanceCore`, Default Host Management Configuration, or a hybrid activation). The landing zone launches no EC2 instances itself. Its ECS Fargate services are not affected. The install association never runs at apply time (`apply_only_at_cron_interval = true`): the first install is the next Sunday 03:00 UTC.

The default baseline OS is now Amazon Linux 2023 (input `patch_operating_systems`, default `["AMAZON_LINUX_2023"]`). Amazon Linux 2 reached end of support on 2026-06-30. `patch_operating_system` (single OS) is deprecated and now defaults to `null`.

What you see on the next apply of aws-security and of each aws-workload:

- two new `aws_ssm_association` resources;
- a new `aws_ssm_patch_baseline` `org-patch-baseline-amazon-linux-2023` set as the default Amazon Linux 2023 baseline;
- the existing `org-patch-baseline` (Amazon Linux 2) and its default binding move to the `["AMAZON_LINUX_2"]` key. With the new default they are then destroyed, and AWS's predefined `AWS-AmazonLinux2DefaultPatchBaseline` becomes the Amazon Linux 2 default again.

What to do:

1. Find the managed instances that will be patched: `aws ssm describe-instance-information` in each account and region. Check that their workloads tolerate a reboot on Sunday 03:00 UTC.
2. To keep scan-only: aws-workload `enable_patch_install = false`; aws-security `aws_overrides.enable_patch_install = false`.
3. An account that still runs Amazon Linux 2 keeps its custom baseline with `patch_operating_systems = ["AMAZON_LINUX_2", "AMAZON_LINUX_2023"]` (aws-workload variable, or `aws_overrides.patch_operating_systems` in aws-security). The AL2 baseline keeps its name, so it is not replaced.
4. To narrow the reboot scope, limit the install to tagged instances: aws-workload `patch_install_target_tag = { key = "PatchInstall", value = "true" }`; aws-security `aws_overrides.patch_install_target_tag`. Only instances with that tag are then patched and rebooted; the daily scan still covers every managed instance. If you already patch with a Quick Setup patch policy or a maintenance window, set `enable_patch_install = false` so instances are not patched twice.

#### ECS services autoscale in production by default (aws-workload, breaking)

A production ECS service that leaves `enable_autoscaling` unset now gets a CPU target-tracking policy: 2 to 10 tasks (`autoscaling_min_capacity`, `autoscaling_max_capacity`), 70 percent CPU. Before, the default was a fixed `desired_count`. More tasks cost more. Set `enable_autoscaling: false` on a service to keep a fixed count. Production means `aws.workload_environments.<env>.is_production: true` in `config/landing-zone.yaml`, or the `is_production` variable of `envs/aws/workload`. The environment name is not read. Non-production services stay fixed unless you set `enable_autoscaling: true`.

A service that has no GitHub deploy role is deployed by Terraform and has its `desired_count` reset on every apply. See `docs/known-gaps.md`.

#### The phase-0 management stack: plan-role read deny, admin role trusts only aws-organization (breaking)

**Breaking for a stack update that takes the template default.** `templates/aws/bootstrap/phase0-management.yaml` changes in two ways:

- `tfc-mgmt-plan` gets an inline `data-read-deny` policy. It is the same deny as the member-account `tfc-plan` role (`tfc-oidc-baseline`): object contents, secret values, parameters, decrypt, table items, log events, API key values and more. No management-account root plans a resource whose refresh needs these reads.
- `TrustSecurityAndBackup` now defaults to `"false"`. With `"false"`, the admin role `tfc-mgmt-apply` trusts only `aws-organization`.

What to do:

1. Check which apply role `aws-security` and `aws-backup` use: their `TFC_AWS_APPLY_ROLE_ARN` workspace variable. With `enable_tfc_management_roles` (default true) and `aws_organization_outputs_from_tfc = true`, tfc-admin binds `tfc-mgmt-aws-security-apply` and `tfc-mgmt-aws-backup-apply`. If either still uses `tfc-mgmt-apply`, apply `aws-organization` and then tfc-admin first, so both are bound to their dedicated roles.
2. Update the stack with the new template. `aws cloudformation deploy` keeps the current value of every parameter you do not override, so an existing stack keeps `TrustSecurityAndBackup`. `aws cloudformation update-stack` and the console take the new default `"false"` unless you pass `ParameterKey=TrustSecurityAndBackup,UsePreviousValue=true`.
3. Once step 1 is done, set `TrustSecurityAndBackup=false` if it is still `"true"`. Keep `"true"` only when `enable_tfc_management_roles = false`: then `aws-security` and `aws-backup` have no other management apply role.

The deny is added with any update of the stack, whatever the parameter values.

#### The phase-0 roles cannot edit themselves or reach member accounts (breaking)

**Breaking for the legacy fallback that assumes `OrganizationAccountAccessRole` from `tfc-mgmt-apply`.** `templates/aws/bootstrap/phase0-management.yaml` gives `tfc-mgmt-plan` and `tfc-mgmt-apply` a new inline policy `deny-self-tampering`:

- `DenyManagementRoleTampering` denies attach, detach, put and delete of role policies, boundary changes, trust updates, `UpdateRole`, `DeleteRole`, `TagRole` and `UntagRole` on `tfc-mgmt-plan`, `tfc-mgmt-apply` and `OrganizationBreakGlass`.
- `DenyMemberAccountPivot` denies `sts:AssumeRole`, `sts:TagSession` and `sts:SetSourceIdentity` on `arn:<partition>:iam::*:role/OrganizationAccountAccessRole`.

These are the same actions that the dedicated `tfc-mgmt-<workspace>-*` roles are denied (`modules/aws/iam/tfc-management-roles`). No Terraform root needs them: `aws-organization` has no `assume_role` and manages only the dedicated `tfc-mgmt-<workspace>-*` roles, which are not covered.

What to do:

1. If a run of `aws-security`, `aws-backup` or `aws-identity` starts from `tfc-mgmt-apply` and assumes `OrganizationAccountAccessRole` (no TFC dynamic credentials for the member account, or `assume_role_arn` set), move it to TFC dynamic credentials first (`docs/runbooks/aws-bootstrap.md`). The legacy fallback still works from break-glass or a human administrator.
2. Update the stack with the new template (`aws cloudformation deploy` keeps your parameter values). The policy takes effect only after this update.
3. To change the three phase-0 roles later, update the stack as a human administrator, not as `tfc-mgmt-apply`.

#### Production gateway endpoints reach only organization resources (aws-workload, breaking)

**Breaking for production workloads that use S3 or DynamoDB outside the organization.** The S3 and DynamoDB gateway endpoints of a spoke route that traffic past the hub egress firewall. With `is_production: true`, the next `aws-workload-<env>` plan now adds endpoint policies (in place, no replacement):

- S3 and DynamoDB are allowed only on resources whose account is in the organization (`aws:ResourceOrgID`). There is no statement for AWS service principals: the AWS data-perimeter examples carry one, but it has no effect on a gateway endpoint.
- S3 also allows `s3:GetObject` on the AWS-owned buckets of the region that AWS documents for ECR image layers, Amazon Linux 2 and 2023 repositories, SSM Agent and Patch Manager.

Requests from the VPC to any other bucket or table (a public dataset, a vendor bucket, a presigned URL to another organization) are denied. The organization ID comes from the `aws-organization` contract. A plan with no `organization_id` there (an old state, or an `aws.contracts.organization` block without it) fails at `terraform_data.gateway_endpoint_policy_inputs` and names the key.

What to do before the plan:

1. Make sure the organization ID reaches the root: re-apply `aws-organization`, or add `organization_id` under `aws.contracts.organization` in `config/landing-zone.yaml`.
2. List the S3 buckets outside the organization that production workloads read through the VPC (VPC flow logs or S3 server access logs). Add each as `arn:aws:s3:::<bucket>/*` to `gateway_endpoint_extra_s3_arns` (read-only).
3. If a workload must write outside the organization, or you cannot list the buckets yet, set `enable_gateway_endpoint_policies = false` on that workspace and record why. The endpoints then get the AWS default full-access policy back (`{"Version":"2008-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"*","Resource":"*"}]}`), sent explicitly, so this also undoes an earlier apply. An endpoint that never had a policy shows no diff.

Non-production workloads keep full-access endpoints unless they set `enable_gateway_endpoint_policies = true`.

#### `.amazonaws.com` in the egress allowlist warns (aws-network)

`aws.network.egress_domain_allowlist` no longer lists `.amazonaws.com` in `config/landing-zone.example.yaml`. That entry admits every S3 bucket and AWS API in any account. aws-network now warns (a `check`, the plan still passes) when the list contains `.amazonaws.com`, `amazonaws.com` or `*.amazonaws.com`. Replace it with the regional service names your workloads call that have no VPC endpoint. For the default app golden path these are `api.ecr.<region>.amazonaws.com`, `.dkr.ecr.<region>.amazonaws.com` and `secretsmanager.<region>.amazonaws.com`. Add `sqs.<region>.amazonaws.com` when a service sets a `queue`. The default `bootstrap_image` comes from `public.ecr.aws`, and its layers from a CloudFront host that AWS does not document: allow both (find the host in the firewall ALERT logs) or push the image to your own ECR. These names match any account, so they do not stop calls to another account's ECR repositories or secrets (`docs/known-gaps.md`). The hub interface endpoints serve `ec2`, `ssm`, `ssmmessages`, `ec2messages`, `kms`, `logs` and `sts`. With `aws:drop_established`, a call to any other AWS API that is not listed is dropped, so check the firewall ALERT logs after the change.

#### Log-archive retention and lock mode from config (aws-security)

The log-archive bucket retention is now set from `compliance.audit_log_retention_days` in `config/landing-zone.yaml`, the same key as the GCP audit bucket. `aws_overrides.log_archive_retention_days` wins over it. With neither set it stays 365 days, and the plan does not change. `aws_overrides.log_archive_object_lock_mode` sets the Object Lock mode for new objects (default `COMPLIANCE`).

The plan fails when:

- the retention is below the floor of a listed `compliance.frameworks` entry (pci_dss 365, hipaa 2190, fedramp_moderate 913 days); or
- `compliance.frameworks` is set and the lock mode is `GOVERNANCE`.

A floor is a minimum. It does not prove that a framework is met.

What a change does:

- The value is the bucket's Object Lock default retention and its lifecycle expiry. Objects still move to Glacier after 90 days, or at expiry when the retention is shorter.
- The default retention applies to new objects only. Objects already written in COMPLIANCE mode keep their retain-until date. Nobody, including the root user, can shorten it.
- A higher value keeps every new log object for longer, so storage cost rises. Each new object stays locked for the full period, and you cannot shorten it later.
- A lower value applies to new objects only and makes the lifecycle expire objects sooner.
- Apply it through the `aws-security` workspace. The deny-tamper SCP statement `DenyLogArchiveObjectLockTampering` lets only the pipeline roles and break-glass change the bucket configuration.

#### **Breaking:** Aurora clusters are tagged for the organization backup policy (rds-aurora, app-services)

`modules/aws/data/rds-aurora` now tags every cluster `backup = true` (new input `enable_org_backup`, default `true`). The organization BACKUP_POLICY from `aws-backup` selects resources by this tag, so after the next apply of each workload that uses the module, AWS Backup also backs up its Aurora clusters daily and keeps each recovery point for 365 days. The RDS automated backups do not change.

What you see on apply: an in-place tag update on each `aws_rds_cluster`. No replacement.

What to do:

- Expect AWS Backup storage cost for each Aurora cluster in the member vault.
- To keep a cluster out of the organization backup, set `enable_org_backup = false` in the `database` block of that service (`services.<name>.database` in the `aws.workload_environments.<env>` entry of `config/landing-zone.yaml`, or in the `services` variable of `envs/aws/workload`). The default is `true`. If you call `modules/aws/data/rds-aurora` directly, set the module input `enable_org_backup`.
- For cross-account copy to the central copy vault (below), the cluster's `kms_key_id` key policy must let the backup account use the key. Otherwise the copy job for that cluster fails.

#### Central backup copy to a locked vault (opt-in, IRREVERSIBLE lock) (aws-backup)

No change unless you opt in. With the defaults the `aws-backup` plan changes no backup resource: the BACKUP_POLICY document is now built with `jsonencode()` instead of a template file, with the same content, and the restore-testing plan and selection move in state (`moved` blocks).

You opt in with `compliance.backup.copy_to_central_vault: true` in `config/landing-zone.yaml` (or `enable_central_copy = true` on the root). A new `make init --profile production` scaffold writes that line for you; a starter scaffold does not, and an existing config file does not change. Apply `aws-organization` first with the same `compliance.backup` settings: it creates the `<vault_name>-cmk` member vaults and their keys. Then apply `aws-backup`. It:

- creates `org-backup-copy-vault` in the backup account, encrypted with a new customer managed key (alias `backup-copy-vault`, rotating, tagged `protected = true`), with a **Compliance-mode Vault Lock**, and a vault access policy that accepts copies only from your organization
- enables org-wide cross-account backup (`aws_backup_global_settings`) in the management account
- points the BACKUP_POLICY at `<vault_name>-cmk` in each member account and copies every recovery point to the copy vault, kept for `compliance.backup.copy_retention_days` (default 365)
- with `compliance.backup.dr_region`, also copies every recovery point to `<vault_name>-cmk` in that region of the same member account, kept 35 days. `dr_region` alone, without the central copy, does only this cross-region copy.
- moves restore testing from the empty `org-backup-vault` to the copy vault (EBS, EC2, RDS, Aurora, S3, DynamoDB, EFS). Unless you pass `restore_testing_role_arn`, it uses a new role, `aws-backup-restore-testing-copy`. The old restore-testing plan, selection and role are destroyed. The old `org-backup-vault` in the backup account stays; it is locked and empty.

What you cannot undo:

- The copy vault lock is in Compliance mode. `changeable_for_days` (default 3) is your window to back out: during those days after the apply you can still delete the lock (`aws backup delete-backup-vault-lock-configuration --backup-vault-name org-backup-copy-vault` in the backup account, as break-glass: the `tfc-apply` boundary denies it, see below) and then delete the vault's recovery points and the vault. After that window nobody can remove the lock or delete the vault while it holds recovery points, including the root user and AWS, and recovery points in it cannot be deleted before `min_retention_days`.
- Turning `copy_to_central_vault` off again stops the copies, but the plan stops at the copy vault key's deletion guard (`prevent_destroy`). Keep the key, or remove the guard from state first as the kms-key module describes.
- Check `min_retention_days` (default 7), `max_retention_days` (default 3650) and `copy_retention_days` before the apply. `copy_retention_days` must lie between the two. Otherwise the plan fails first, on the validation in `modules/aws/stages/backup/variables.tf`. After the window you cannot lower `max_retention_days` or raise `min_retention_days` beyond what the lock allows.
- The copy vault key is tagged `protected = true`. Only break-glass can disable it, schedule its deletion or change its key policy. Its key policy names the backup account's `break-glass` role (`copy_vault_key_policy_admin_role_name`), which must exist before the apply (aws-organization `enable_member_break_glass_role`, default on). Later changes to the key policy fail as the pipeline; apply them as break-glass.

What cross-account copy also needs:

- Each source resource's key must be shareable with the backup account. Aurora and RDS encrypted with a customer managed key need a key policy that lets the backup account use the key.
- EBS volumes encrypted with the AWS managed `aws/ebs` key cannot be copied across accounts. Use a customer managed key for EBS (for example `account-baseline` `kms_key_arn`) before you rely on the copy.
- The copy runs only for resources the BACKUP_POLICY selects (tag `backup = true`).

#### Opt-in customer managed key member backup vaults (aws-organization)

No change unless you opt in. With the defaults the Backup service-role StackSet template stays the same, so the plan shows no StackSet change.

You opt in with `compliance.backup.copy_to_central_vault: true` or `compliance.backup.dr_region` in `config/landing-zone.yaml`, or with `member_backup_vault_encryption = "cmk"` on the root. Then the StackSet `aws-backup-org-role` adds two resources to every Workloads-OU account:

- a customer managed KMS key with rotation on, tagged `protected = true`, whose policy lets the backup account use it for copy jobs
- a second vault, `<member_backup_vault_name>-cmk` (default `org-backup-vault-cmk`), encrypted with that key

Cross-account copy needs a customer managed key on the source vault, and AWS Backup cannot change the key of an existing vault. So the original `org-backup-vault` is kept, with its recovery points. It ages out under its lifecycle.

What operators see on apply:

- One StackSet update operation that updates the stack in every Workloads-OU account, 10 accounts at a time, with zero failure tolerance. One failed account stops the operation. Read the stack events in that account, fix the cause, and apply again.
- With `compliance.backup.dr_region` (or `member_backup_dr_region`), a second StackSet, `aws-backup-org-role-dr-vault`, creates the same key and vault in that region in every Workloads-OU account. The region must be in `aws.allowed_regions` and must differ from `org.regions.aws`.
- Accounts that join the Workloads OU later get both through auto-deployment.

What you cannot undo:

- After the key exists, the deny-tamper SCP lets only break-glass change its key policy, disable it, turn off rotation, remove its `protected` tag or schedule its deletion. The StackSet execution role is not break-glass. A later template change that edits the key policy fails in each account. This includes a new backup account ID. Plan such a change as a break-glass operation.
- The key and both vaults have `DeletionPolicy: Retain`. If you turn the option off again, the StackSet stops managing them but does not delete them. Delete them by hand as break-glass after their recovery points expire.

Apply `aws-organization` before `aws-backup`, so the vaults exist before a backup policy names them.

#### The tfc-plan read deny is now a managed policy with more actions (aws-organization)

The plan-role deny moves from an inline policy on each `tfc-plan` role to one managed policy per account, `tfc-plan-data-read-deny`. It now also denies:

- API Gateway key values
- launch-template and launch-configuration user data
- CodeBuild project and build variables
- Lambda layer code
- Cognito app-client secrets
- AppSync API keys
- Step Functions execution data
- Lightsail access details
- Glacier job output
- Elastic Beanstalk configuration

What to do:

- A stack that plans a launch template, a CodeBuild project or a similar resource must add its ARN to `plan_role_data_read_exempt_arns`.
- A stack that plans REST API keys must set `enable_plan_role_data_read_deny = false`.

The StackSet update creates the policy and removes the old inline policy.

#### The tfc-apply boundary protects the locked backup copy vault (aws-organization)

The embedded `tfc-apply-boundary` (tfc-oidc-baseline) has a new statement, `DenyProtectedBackupVaultUnlock`. In every member account it denies `tfc-apply` `backup:DeleteBackupVaultLockConfiguration`, `backup:DeleteBackupVaultAccessPolicy` and `backup:DeleteBackupVault` on the vaults in `protected_backup_vault_names` (default `org-backup-copy-vault`, the aws-backup central copy vault). The next aws-organization apply updates the StackSet. Creating the vault, its lock and its access policy stays allowed, so the first aws-backup apply is unaffected.

What changes for you: with central copy on, a Terraform change that deletes or replaces the copy vault's lock or access policy, or the vault itself, fails as the pipeline. Apply it as break-glass, within `changeable_for_days` for the lock. The tfc-oidc-baseline input `protected_backup_vault_names` lists the vaults; the organization stage keeps its default. `PutBackupVaultLockConfiguration` and `PutBackupVaultAccessPolicy` are not denied (docs/known-gaps.md).

#### The tfc-apply boundary locks role trusts and foreign policy versions (aws-organization, breaking)

**Breaking for trust changes on existing roles.** The embedded `tfc-apply-boundary` (tfc-oidc-baseline) has four changes. The next aws-organization apply updates the StackSet in every member account.

- `DenyTrustPolicyUpdates` denies `iam:UpdateAssumeRolePolicy` on every role. A new role is unaffected, because `CreateRole` sets its trust.
- `DenyForeignPolicyVersioning` denies `iam:CreatePolicyVersion` and `iam:SetDefaultPolicyVersion` outside `arn:<partition>:iam::<account>:policy/tfc-managed/*`.
- `DenyGroupUserAndLoginProfileEscalation` denies `iam:CreateGroup`, group and user policies, `iam:AddUserToGroup` and `iam:UpdateLoginProfile`.
- `DenyProtectedKeyTampering` also denies `kms:UpdateAlias` and `kms:DeleteAlias` when the current or the target key is tagged `protected = true`. The deny-tamper SCP (`DenyProtectedKeyDestruction`) denies the same two actions to every member principal except break-glass.

What changes for you:

- A Terraform change to the trust policy of an existing role in a member account fails as `tfc-apply`. Examples: a new GitHub `ref` or `environment` on an app-services deploy role, a changed `trust_policy` in `modules/aws/iam/iam-role`, or a new forensics account on the incident-response snapshot role. Apply the change as break-glass, or replace the role in the run (`-replace=<address>`). To turn the lock off, set `tfc_enable_apply_trust_update_lock = false` on the organization stage (`enable_apply_trust_update_lock` on tfc-oidc-baseline).
- A customer-managed policy that `tfc-apply` creates and later changes must use `path = "/tfc-managed/"`. No module in this repo creates one.
- Renaming the alias of a protected key, or pointing it at another key, needs break-glass. Creating the key and its alias together is unaffected.

#### The deny-tamper SCP protects StackSet-owned policies (aws-organization)

The new statement `DenyStackSetPolicyTampering` limits who can create, version, delete or tag `tfc-apply-boundary` and `tfc-plan-data-read-deny`. Only break-glass and the StackSet execution role can. Configure the names with `stackset_managed_policy_names`. An external boundary set through `apply_permissions_boundary_arn` is not covered.

#### StackSet stacks are written only by the StackSet (aws-organization, breaking)

**Breaking for anyone who updates a `StackSet-*` stack directly in a member account.** A
StackSet creates a stack named `StackSet-<stack set name>-<id>` in each target account.
CloudFormation does not report a direct update of that stack as StackSet drift, so a member
principal could rewrite the StackSet-owned roles and the `tfc-apply` boundary that way. The next
`aws-organization` apply changes two things:

- The deny-tamper SCP gets `DenyStackSetStackTampering`. In every member account it denies
  `cloudformation:CreateStack`, `UpdateStack`, `DeleteStack`, `RollbackStack`,
  `CreateChangeSet`, `ExecuteChangeSet`, `CreateStackRefactor`, `ExecuteStackRefactor`,
  `SetStackPolicy`, `UpdateTerminationProtection`, `ContinueUpdateRollback` and
  `CancelUpdateStack` on `arn:<partition>:cloudformation:*:*:stack/StackSet-*`. Only break-glass,
  the roles in `stackset_execution_role_names` (default `stacksets-exec-*`) and the roles in the
  new `stackset_stack_writer_role_names` (default empty) are exempt.
- The `tfc-apply` boundary gets `DenyStackSetStackTampering`, which denies `cloudformation:*Stack`,
  `*ChangeSet`, `*StackRefactor`, `SetStackPolicy`, `UpdateTerminationProtection` and
  `ContinueUpdateRollback` on `arn:*:cloudformation:*:*:stack/StackSet-*`. With
  `apply_permissions_boundary_arn` set, the deny is inline on the apply role. The StackSet updates
  the boundary in every member account. A new precondition fails the `aws-organization` plan when
  the boundary is over the 6,144-character quota after `Fn::Sub` substitution.

What to do before the apply:

1. Find stack writes that are not made by a service-managed StackSet. In each member account,
   search CloudTrail for `UpdateStack`, `DeleteStack` and `ExecuteChangeSet` on `StackSet-*`
   stacks whose caller is not `stacksets-exec-*`.
2. **AWS Control Tower estates must act before the apply.** Control Tower deploys its own stacks
   into enrolled accounts, named `StackSet-AWSControlTower*` (for example
   `StackSet-AWSControlTowerBP-BASELINE-ROLES`), and manages accounts through the
   `AWSControlTowerExecution` role. Set `aws.stackset_stack_writer_role_names:
   [AWSControlTowerExecution]` in `config/landing-zone.yaml` (or the `aws-organization` variable
   `stackset_stack_writer_role_names`, which wins), or Control Tower updates, repairs and
   enrollments fail on those stacks. Each entry needs at least 3 literal characters before the
   first `*`. The same applies to a
   self-managed StackSet (add its execution role, for example
   `AWSCloudFormationStackSetExecutionRole`) and to AWS Systems Manager Quick Setup (add its local
   execution role). A writer role is exempt from `DenyStackSetStackTampering` only. It is not
   exempt from any other deny-tamper statement, and it is not made break-glass-only.
3. Do not fix a stuck StackSet stack by hand in the member account. Retry the StackSet operation
   from the management account, or use break-glass.

#### The log-archive SCP covers all bucket configuration changes (aws-organization)

On the log archive and its access-log bucket, the SCP now denies:

- replication, encryption, lifecycle and inventory configuration
- every `s3:PutBucket*` change
- bucket deletion

Pipeline roles and break-glass stay exempt, as before (ADR 0014).

#### The region SCP exempts the member break-glass role (aws-organization)

The exemption is now `arn:<partition>:iam::*:role/<break-glass name>`. The management-account ARN it used before had no effect, because SCPs never apply to the management account.

#### Log-archive access logs go to a companion bucket (aws-security)

By default the module creates `<log_archive_bucket_name>-access-logs`, with SSE-S3 and no Object Lock. The archive can no longer log to itself. A bucket name longer than 51 characters needs `access_log_bucket`.

#### CloudTrail log-archive grants are pinned to the trail owner (aws-security)

The CloudTrail grants now also require an `aws:SourceArn` trail pattern for the management account (`cloudtrail_trail_account_id`, set by the security stage).

#### The forensics role can be assumed (aws-security)

The trust and KMS conditions now use `aws:PrincipalAccount` and `aws:PrincipalOrgID`. The previous service-principal keys meant no IAM principal could assume the role.

#### AWS KMS keys and the log archive have deletion guards (aws-security, aws-organization)

`kms-key`, `cloudtrail-org` and `log-archive-bucket` add a `prevent_destroy` guard (`enable_deletion_protection`, default true). The guard-alerts key has `prevent_destroy`. A plan that destroys or replaces one of these resources now fails. To retire one deliberately, set `enable_deletion_protection = false` and apply first, or run `terraform state rm` on its guard.

#### AWS network addressing moves to the CIDR plan (aws-network, aws-workload, tfc-admin)

**Breaking for an applied aws-network.** The aws-network defaults sat inside
the GCP block (`top_cidr` `10.0.0.0/8`, inspection `10.0.0.0/16` and egress
`10.1.0.0/16`, the GCP hub and DNS ranges). They now follow
[the CIDR plan](docs/architecture/cidr-plan.md): `top_cidr` `10.64.0.0/10`,
regional pool `10.64.0.0/12`, inspection `10.64.0.0/16`, egress `10.65.0.0/16`.
The aws-workload built-in `vpc_cidr` moves from `10.20.0.0/16` to
`10.72.0.0/16`. All four network values can now be set in
`aws.network.{top_cidr,regional_cidrs,inspection_cidr,egress_cidr}`.

**Before the upgrade apply,** if aws-network is already applied, pin its current
ranges in `config/landing-zone.yaml` (`aws.network.top_cidr: 10.0.0.0/8`, and so
on), or the plan replaces the IPAM pools and hub VPCs. Do the same for a
workload that relied on the `10.20.0.0/16` default (`vpc_cidr`). Then plan
tfc-admin: it now fails on any overlap between GCP and AWS ranges in the config
file, naming each pair. Move whichever cloud's ranges the plan names.

#### Member-account backup vault (aws-organization)

**Behaviour change.** The org `BACKUP_POLICY` writes to `org-backup-vault` in
each member account, but the repo only created that vault in the backup account,
so scheduled jobs in workload accounts had no target. The Backup service-role
StackSet now also creates `AWS::Backup::BackupVault` (`member_backup_vault_name`,
default `org-backup-vault`, AWS managed key, retained on stack deletion) in
every Workloads-OU account (`create_member_backup_vault`, default `true`).

Manual steps:

1. If you renamed aws-backup `vault_name`, set the same value in
   aws-organization `member_backup_vault_name`.
2. If a member account already has a vault of that name (created by hand or
   another tool), the stack instance fails to create it. Either delete the
   empty vault first, or set `create_member_backup_vault = false` and keep
   managing it yourself.
3. Apply `aws-organization`. The StackSet updates every existing stack
   instance in place.

#### Suspended deny-all and Sandbox guard SCPs (aws-organization)

Two SCPs are created and attached by default, but only when the `Suspended` /
`Sandbox` OU exists. `scp-suspended-deny-all` denies every action in the
Suspended OU except break-glass and `stacksets-exec-*`. `scp-sandbox-guard`
limits Sandbox to the `sandbox_allowed_instance_types` families (default
`t3`/`t4g` micro to large), and denies `directconnect:*`, VPC peering and
`organizations:*`. SCPs never touch the management account. **To opt out,** add
`scp-suspended-deny-all` / `scp-sandbox-guard` to `disabled_org_policies`
(its default is `["backup-policy"]`, so repeat that entry); their attachments
drop with them. Check that nothing you run lives in Sandbox/Suspended first.

#### The region SCP no longer exempts the Terraform run role (aws-organization)

`scp-region-restriction` used to carve the `tfc-apply` run role
(`terraform_run_role_arn`) out of its deny; break-glass is now the only
exemption. Global-endpoint services stay in `NotAction`, which also gains
`networkmanager:*` and `notifications:*`. The next aws-organization apply
updates the SCP **in place**, and from then on a member-account pipeline call
to a service outside `NotAction` in a region outside `allowed_regions` is
denied. **Before upgrading,** check that no layer manages resources in a region
outside `allowed_regions` (a provider alias in another region, a resource with
an explicit `region`); add that region to `allowed_regions` or move the
resource. If an apply fails with an SCP `AccessDenied` afterwards, the service
is missing from `NotAction`: add it in `modules/aws/governance/organization-policy`
or apply with break-glass (`docs/known-gaps.md`, "Region SCP no longer exempts
the run role").

#### Plan roles are denied more data-plane reads (aws-organization)

The `DenyDataPlaneReads` statement on the `tfc-plan` roles (the member-account
baseline from `tfc-oidc-baseline`, and the management-account plan roles from
`tfc-management-roles`) also denies `ssm:GetCommandInvocation`,
`logs:GetLogRecord`, `rds:DownloadDBLogFilePortion`, `es:ESHttpGet`,
`cassandra:Select`, `codecommit:GitPull` and `codecommit:GetFile`; the
management plan roles additionally lose `s3:GetObject*`,
`secretsmanager:BatchGetSecretValue` and `kms:GenerateDataKey*`. The next
aws-organization apply updates the policies in place (the member baseline
through its StackSet). A plan that reads content through a data source with
one of these actions (for example an `aws_s3_object` body in the management
account) now fails with `AccessDenied`; move such reads to the apply run or
out of Terraform. tfc-admin also adds `aws-shared-services` to
`speculative_disabled_workspaces` (in-place workspace update: PRs no longer run
speculative plans there).

#### Three more default AWS permission sets (aws-identity)

The `permission_sets` default grows from `AdministratorAccess` + `ReadOnly` to
also include `PlatformAdmin` (AdministratorAccess, 4 h), `Developer`
(PowerUserAccess, 8 h) and `SecurityAudit` (SecurityAudit, 4 h). The next
aws-identity apply **creates** the three permission sets (unassigned until you
assign them, but provisioned). Assignments now also accept
`group_display_name` and `account_key`, and `aws.identity.groups` derives them
from config. **To opt out,** set `permission_sets` on aws-identity to the
previous two entries only:

```hcl
permission_sets = {
  AdministratorAccess = { description = "Full administrative access. Assign only to break-glass groups.", session_duration = "PT1H", managed_policy_names = ["AdministratorAccess"] }
  ReadOnly            = { description = "Organization-wide read-only access for auditors and viewers.", session_duration = "PT1H", managed_policy_names = ["ReadOnlyAccess"] }
}
```

#### Spoke VPCs request their CIDR explicitly from IPAM (aws-workload)

**Breaking: the default changes.** An IPAM-backed VPC from
`modules/aws/network/vpc` now requests `cidr_block` explicitly from the pool
(`ipam_allocation` defaults to `explicit_cidr`; aws-workload's
`ipam_explicit_cidr` defaults to `true`). The legacy shape asked IPAM for any
block of `netmask_length` (`/16`), but the subnets are always cut from
`cidr_block` (`vpc_cidr`, default `10.72.0.0/16`). When IPAM returned another
block, subnet creation failed with `InvalidSubnet.Range`.

The VPC now has `lifecycle { ignore_changes = [ipv4_netmask_length] }`. An
existing netmask-shape VPC keeps its id: its state already holds the allocated
`cidr_block`, and the provider clears a `cidr_block` diff while
`ipv4_netmask_length` is set. A new `check` block
(`ipam_allocation_matches_subnet_math`) warns when the allocated block differs
from `cidr_block`. A side effect: a later `netmask_length` change on a legacy
VPC no longer replaces it.

For each existing `aws-workload-<env>` that allocates from IPAM:

1. Read the VPC's real block. Run
   `terraform state show 'module.aws_workload.module.vpc.aws_vpc.this'` in a
   speculative plan, or open the TFC state viewer, and read `cidr_block`.
2. If it differs from `vpc_cidr`, set
   `aws.workload_environments.<env>.vpc_cidr` to that block before you apply.
   The subnets could not be created in that VPC, so this only fixes the subnet
   math. The upgrade plan also prints the check warning for this VPC.
   If that block is the inspection or egress VPC range, do not adopt it: the
   VPC overlaps a hub VPC. Follow the recovery in
   [The static hub VPC ranges are reserved in the IPAM pool](#the-static-hub-vpc-ranges-are-reserved-in-the-ipam-pool-aws-network).
3. If you must keep the old shape, set `ipam_explicit_cidr = false`
   (aws-workload) or `ipam_allocation = "netmask"` (direct module callers).

What is proven: mock tests prove the planned shape (pool + `cidr_block`, no
netmask). A real `hashicorp/aws` 6.72.0 plan with a hand-made state
(`-refresh=false`, no AWS API calls) showed no change for a netmask-shape VPC,
and a replacement for the same move without `ignore_changes`. What still needs
the sandbox: a plan of `aws-workload-dev` against its real state after the
upgrade shows no VPC change, and a real explicit-CIDR allocation from an IPAM
pool (see `docs/known-gaps.md`).

#### IPAM explicit-CIDR allocation for hub VPCs is opt-in (network-hub stage)

Hub VPCs that allocate from IPAM pass `ipam_allocation = "explicit_cidr"`.
`ipam_new_vpcs` (default `[]`) lists hub VPCs to create from the pool, and
`ipam_mode_for_new_vpcs_only` (default `true`) guards the rest. Adding a pool
to an existing static VPC replaces it. No manual step on upgrade.

Release race: listing a static hub VPC in `ipam_new_vpcs` also removes its
`hub_static` reservation in the same apply. Terraform does not order that
release before the new VPC's allocation, and IPAM releases asynchronously, so
the VPC create can fail with an overlapping-allocation error. Wait a few
minutes and apply again.

#### The static hub VPC ranges are reserved in the IPAM pool (aws-network)

**Breaking: the aws-network plan adds resources, and the apply fails if a spoke
already holds a hub range.** The inspection and egress VPCs keep their static
CIDRs, so they are not IPAM allocations. IPAM did not know those ranges were in
use and could allocate them to a spoke. With the defaults, the regional pool
(`10.64.0.0/12`) starts at the inspection VPC (`10.64.0.0/16`), so the first
legacy netmask-shape spoke could receive it.

aws-network now plans one `aws_vpc_ipam_pool_cidr_allocation.hub_static` per
static hub VPC whose CIDR is inside the home-region pool (`aws_region` in
`regional_cidrs`). The allocation only reserves address space; it does not
change the VPC. A hub VPC that allocates from the pool (`ipam_new_vpcs`, or
`ipam_mode_for_new_vpcs_only = false`) needs no reservation. A hub VPC outside
the pool CIDR is not reserved. A hub VPC that only partly overlaps the pool
fails the plan: move `inspection_cidr` or `egress_cidr` inside the pool CIDR or
out of it. Every argument of the allocation forces replacement (checked against
`hashicorp/aws` 6.72.0), so the reservation is released and taken again if a
hub CIDR or the pool changes.

The aws-network plan cannot see a conflict. No `hashicorp/aws` 6.72.0 data
source lists the allocations in a pool. A conflict shows up at apply, when the
allocation is created: that one resource fails, the VPCs are not changed, and
the rest of the run still applies. tfc-admin already fails its plan when a `vpc_cidr` in
`config/landing-zone.yaml` overlaps a hub CIDR, so the risk is a spoke with no `vpc_cidr`
match: an IPAM-backed VPC created in the legacy netmask shape.

Before you apply aws-network:

1. In the network account, list the regional pool's allocations:
   `aws ec2 get-ipam-pool-allocations --ipam-pool-id <regional pool id>`
   (the pool id is in the aws-network output `ipam_pool_ids`).
2. If no allocation overlaps `inspection_cidr` or `egress_cidr`, apply. Nothing
   else is needed.
3. If a spoke VPC holds a hub range, move that spoke first. Set
   `aws.workload_environments.<env>.vpc_cidr` to a free block inside the
   regional pool and apply its `aws-workload-<env>`. This replaces the spoke VPC
   (the destroy guard asks for an override), and the old allocation is released
   with it. IPAM can take some minutes to release it. Then apply aws-network;
   if the reservation still fails, wait and run it again.
4. If the aws-network apply already failed on `hub_static`, do steps 1 to 3 and
   queue a new aws-network run. The allocation is created on that run.

A failed allocation leaves no partial state to import. The resource supports
import (`<allocation id>_<pool id>`) if you ever need to adopt a reservation
that was created by hand.

What is proven: mock tests prove which hub VPCs are reserved, the pool id and
CIDR wiring, and the plan failure for a hub that only partly overlaps the pool.
A real `hashicorp/aws` 6.72.0 plan with a hand-made state (no AWS API calls)
showed that a change to `cidr`, `ipam_pool_id` or `description` forces
replacement, and that an import block for this resource type reaches the read
call. What still needs the sandbox: an aws-network apply creates both
reservations in a real regional pool, a spoke that then requests a hub range is
rejected by IPAM, and the static hub VPCs keep working (see
`docs/known-gaps.md`).

#### IPAM pool growth and an OU-scoped pool share are opt-in (aws-network)

Nothing changes unless you set the new keys. The org-wide share keeps its principal and moves in state from `aws_ram_principal_association.org` to `aws_ram_principal_association.org[0]`. A `moved` block does this, so the plan shows one address move and no change in AWS.

- `aws.network.regional_additional_cidrs` adds CIDRs to a region's pool. See [Region pool is full](docs/runbooks/aws-cidr-expansion.md#region-pool-is-full-add-awsnetworkregional_additional_cidrs).
- `aws.network.ipam_share_ou_keys` shares the pools with the listed OUs only (keys of the `aws-organization` `ou_ids` output). **Before you set it, list the OU of every account that already allocates from a pool, child OUs are covered.** An account outside the listed OUs loses RAM access to the pool, so its next VPC (or a replaced one) fails to allocate. Existing VPCs keep their CIDR. The network account owns the pools and needs no listing. To widen the scope again, add the OU key and apply `aws-network`.

#### AWS availability zones follow the region and AZ IDs (aws-network, aws-workload)

**Breaking: both roots now read the account's availability zones at plan
time.** Before, aws-network defaulted to `eu-west-2a` and `eu-west-2b`, and
aws-workload had no zone input, so every spoke used the workload stage default
(the same two zones). In any other region every subnet failed at apply.

aws-network and aws-workload now resolve the zones in this order:

1. `availability_zones` (zone names, explicit variable).
2. `availability_zone_ids` (explicit variable).
3. aws-workload only: `aws.workload_environments.<env>.availability_zone_ids`.
4. `aws.network.availability_zone_ids` in `config/landing-zone.yaml` (both
   roots read it, so the spokes land in the hub's physical zones).
5. The region's first three available zones, sorted by name (Local Zones and
   Wavelength Zones are left out).

The subnets use the first `az_count` zones (aws-workload has a new `az_count`
variable, default 2). An AZ ID (for example `euw2-az2`) names the same physical
zone in every account; a zone name does not. Each root maps the IDs to zone
names in its own account. The subnets still take the zone name
(`availability_zone`), so a subnet whose zone name does not change is not
replaced. A zone ID that the account does not have, or an `az_count` above the
resolved zones, fails the plan.

What changes for an existing estate:

- **eu-west-2 on the old defaults:** no change. The region default resolves to
  `eu-west-2a`, `eu-west-2b` and `eu-west-2c`, and `az_count = 2` uses the
  first two, as before.
- **You set `availability_zones`:** no change. Explicit names win and the
  zone lookup is skipped.
- **Plan permissions:** the plan calls `ec2:DescribeAvailabilityZones` in the
  network account and in each workload account. The `tfc-plan` and `tfc-apply`
  roles from `modules/aws/iam/tfc-oidc-baseline` (ReadOnlyAccess) allow it. A
  custom plan role needs that action.
- **Your own `terraform test` suites for these roots:** a bare
  `mock_provider "aws" {}` returns no zones, so the plan fails. Add a
  `mock_data "aws_availability_zones"` block with names and zone IDs for the
  test region (see `envs/aws/network/tests/availability_zones.tftest.hcl`).

**Before you set `aws.network.availability_zone_ids` on an estate that already
has subnets,** know that IDs can change the zone NAMES the roots resolve. A
changed name replaces every subnet in that zone, and everything in those
subnets (NAT gateways, firewall endpoints, TGW attachment ENIs, tasks,
databases). Setting IDs is opt-in; nothing sets them for you.

1. In the network account, run `aws ec2 describe-availability-zones --region
   <region>` and note the `ZoneId` of each zone the hub uses today. Set
   `aws.network.availability_zone_ids` to those IDs, in the same order. Plan
   aws-network: it must show no subnet change.
2. For each `aws-workload-<env>`, plan it. The workload account maps the same
   IDs to its own names, which can differ. If a subnet would be replaced, run
   the same command in that workload account and set
   `aws.workload_environments.<env>.availability_zone_ids` to the IDs of the
   zones it uses today. Plan again: it must show no subnet change.
3. New workloads with no per-environment IDs then land in the hub's zones.

#### Route 53 Resolver endpoints are opt-in; the profile carries DNS settings, not a VPC (aws-network)

**Breaking for direct callers of `modules/aws/network/route53-resolver`.**

- The inbound and outbound Resolver endpoints are now created only with
  `enable_resolver_endpoints = true` (default `false`). In aws-network they
  follow `aws.network.resolver_endpoints.enabled`, else they are on only when
  the VPN is on (`enable_resolver_endpoints` on the root and the stage wins).
- `subnet_ids` and `security_group_ids` now default to `[]`. The old
  defaults were placeholders (`subnet-aaaa`, `sg-aaaaaaaaaaaaaaaaa`), and
  aws-network never passed a security group, so the endpoints could not be
  created. With `security_group_ids` empty the module now owns a security
  group that admits DNS (TCP and UDP 53) from the new input `allowed_cidrs`
  and sends DNS only to the `forward_rules` target IPs. aws-network passes
  `top_cidr` and `vpn.onprem_cidrs`. With BGP, list the on-premises resolver
  ranges in `vpn.onprem_cidrs` too, or they cannot query the inbound
  endpoint.
- `forward_rules` now need `enable_resolver_endpoints = true` (the plan fails
  otherwise), and each rule is also added to the Route 53 Profile.
- The profile no longer lists the egress VPC as a resource
  (`aws_route53profiles_resource_association.vpc`). The Route 53 Profiles API
  accepts only private hosted zones, DNS Firewall rule groups, Resolver rules
  and interface VPC endpoints as profile resources, so that association could
  not be created. The profile now carries the DNS Firewall rule group
  (priority 101), the forward rules and the zones in the new input
  `profile_hosted_zone_arns`.
- `inbound_endpoint_id` and `outbound_endpoint_id` are null when the endpoints
  are off. New outputs: `inbound_endpoint_ips` (module),
  `resolver_inbound_endpoint_ips` and `resolver_endpoints_enabled` (stage),
  and `resolver_inbound_endpoint_ips` (aws-network).

What the plan shows on an existing aws-network estate:

- Nothing changes for the endpoints. They could not be created before, so no
  live endpoint is removed. If an estate does hold an endpoint in state, the
  `moved` blocks keep its address, and with the VPN off it is now destroyed:
  set `aws.network.resolver_endpoints.enabled: true` first to keep it.
- A `aws_route53profiles_resource_association.vpc` in state (normally none, the
  API rejected it) is destroyed.
- The DNS Firewall rule group is added to the profile (create only).

Replacement and outage window: an endpoint's security groups are ForceNew in
the aws provider (checked in v6.72.0). An endpoint that is in state with other
security groups (for example one created outside this module's defaults) is
replaced when it moves to the module-owned group. The new inbound endpoint gets
new IP addresses: on-premises resolvers that forward to the old IPs fail until
you point them at `resolver_inbound_endpoint_ips`. The new outbound endpoint is
replaced in the same apply, and forward rules fail between the destroy and the
create. Do this in a change window.

#### Central interface endpoints get a security group and shared private DNS (aws-network)

**Breaking: the endpoint DNS changes in place.** aws-network now passes
`allowed_cidrs = [top_cidr]` and `enable_shared_private_dns = true` to
`modules/aws/network/vpc-endpoints`. Before, the endpoints had no security
group, so they used the egress VPC default group, which the `vpc` module
strips to deny-all: the endpoints accepted no traffic, even from the egress
VPC. Their private DNS was also visible only inside the egress VPC.

What the plan shows on an existing estate:

- A new security group `interface-endpoints-*` (HTTPS from `top_cidr`).
- Each `aws_vpc_endpoint.interface` updates in place (checked against aws
  provider v6.72.0: `security_group_ids` and, for interface endpoints,
  `private_dns_enabled` are not ForceNew): the default group is replaced by the
  new group, and `private_dns_enabled` goes from `true` to `false`. No endpoint
  is replaced, and the endpoint IPs do not change.
- One new private hosted zone per service (`<service>.<region>.amazonaws.com`)
  with an alias A record to the endpoint, associated with the egress VPC, and a
  profile resource association for each zone (new output
  `shared_dns_zone_arns`).

Outage window: the zones are created after the endpoints stop using their own
private DNS (`depends_on`), because the two names conflict. Between the two
steps, clients in the egress VPC resolve the public service addresses and
reach them through NAT, so AWS API calls keep working. The spokes do not
resolve the endpoint names until they associate the Route 53 Profile. The
change runs in one apply; nothing needs to be done by hand.

Direct callers of the module: nothing changes unless you set
`allowed_cidrs` or `enable_shared_private_dns`. With
`enable_shared_private_dns`, list in `interface_services` only services whose
private DNS name is `<service>.<region>.amazonaws.com`.

#### Spoke VPCs associate the org Route 53 Profile: spoke DNS changes (aws-workload)

`aws-workload-<env>` now creates `aws_route53profiles_association.spoke`
(`workload-<env>-dns-profile`) for its spoke VPC. It reads the profile ID from the
aws-network contract `resolver_profile_id` (remote state, the
`network_contract` variable or `aws.contracts.network.resolver_profile_id`).
Standalone spokes (`enable_network_hub = false`) associate nothing. The plan
shows one create and changes no other resource, but DNS in the spoke changes as
soon as the association is complete:

- The DNS Firewall rule group of the profile applies to every query from the
  spoke. A query for a domain on the block list fails.
- The central interface endpoint zones apply. The names
  `<service>.<region>.amazonaws.com` of the services in the egress VPC
  (default: ec2, ssm, ssmmessages, ec2messages, kms, logs, sts) resolve to the
  endpoint IPs in the egress VPC, not to public AWS addresses. AWS API calls to
  these services then go over the transit gateway to the endpoints. With the
  Network Firewall on, they are inspected on the way (the spoke default route
  goes to the inspection attachment), as before through NAT.
- Any resolver forward rules in the profile apply.

What could break:

- A workload that needs a domain on the DNS Firewall block list.
- AWS API calls that the endpoints refuse. The endpoint policy allows only
  principals in the organization (`aws:PrincipalOrgID`). Calls signed with
  credentials of another AWS account now fail for these services. Test
  unauthenticated STS calls (`AssumeRoleWithWebIdentity`,
  `AssumeRoleWithSAML`) in the sandbox first, because they carry no principal.
- With `aws:drop_established` and an egress domain allowlist, the firewall
  still matches the TLS server name, so the service names must stay on the
  allowlist. Traffic now goes to a private address instead of a public one,
  so check custom Suricata rules that match on the destination.
- A spoke with its own interface endpoint for one of these services, with
  private DNS on, now has two private zones for the same name. Remove that
  endpoint or switch off its private DNS before you apply.
- The endpoint security group admits HTTPS only from `top_cidr`. A spoke
  outside `top_cidr` cannot reach the endpoints.

How to check before you apply, per spoke:

1. List the blocked domains: `aws route53resolver list-firewall-rules
   --firewall-rule-group-id <id>` and `aws route53resolver
   list-firewall-domains --firewall-domain-list-id <id>` in the network
   account. Compare them with the domains the workload uses.
2. List the spoke interface endpoints: `aws ec2 describe-vpc-endpoints
   --filters Name=vpc-id,Values=<spoke-vpc-id>
   Name=vpc-endpoint-type,Values=Interface`. Check `PrivateDnsEnabled`.
3. From an instance in the spoke, call a central endpoint before the DNS
   change, for example `curl -sS -o /dev/null -w '%{http_code}\n' --resolve
   sts.<region>.amazonaws.com:443:<endpoint-ip>
   https://sts.<region>.amazonaws.com/`. Any HTTP status proves the path
   through inspection to the endpoint. A timeout means the firewall or a
   route drops it. Get the endpoint IPs from the network account with
   `aws ec2 describe-network-interfaces` on the endpoint ENIs.
4. Run the `aws-workload-<env>` plan. It must show only
   `aws_route53profiles_association.spoke` to create.

To hold back one environment, set its `network_contract` workspace variable
with `tgw_id` and `ipam_pool_ids` and no `resolver_profile_id`. The root then
plans no association. Remove the variable once the checks pass.

#### Starter spokes egress through NAT; starter rejects the VPN (aws-network, breaking)

**Breaking for a starter estate with the VPN.** A starter estate
(`org.profile: starter`, or `enable_network_firewall = false`) with
`aws.network.vpn.enabled: true` now fails the plan
(`terraform_data.hybrid_needs_inspection`). That combination never forwarded
traffic: the hybrid table sends on-premises traffic to the inspection VPC,
which has no forwarding route without the firewall. Turn the VPN off, or set
`enable_network_firewall = true` (or the `production` profile) and apply.

Starter estates may now list `aws.network.spoke_attachments`. Before, the plan
rejected them. Their spokes egress through NAT **without inspection**: the
`prod` and `nonprod` tables route `0.0.0.0/0` to the egress attachment, and
each spoke propagates into the `shared` table, which the egress attachment
uses for the NAT replies. Accept this before you list spokes on starter.

What the plan shows on an existing starter estate:

- The two TGW routes `prod:default` and `nonprod:default` are replaced: their
  target moves from the inspection attachment to the egress attachment. No
  spoke could be wired on starter before, so no traffic is interrupted.
- Nothing else changes until you list spokes. Each listed spoke then adds an
  accepter (with `accept`), an association and a propagation into `shared`.

Production estates (Network Firewall on) plan no change.

If you later turn the firewall on for a starter estate with spokes, the same
apply moves the segment defaults back to inspection, moves each spoke
propagation from `shared` to `inspection` (replaced) and adds the two
inspection hub routes. Spoke traffic drops while the propagations are
replaced. Do it in a change window.

#### Cross-segment spoke traffic is dropped at the transit gateway (aws-network, breaking)

**Breaking: prod to nonprod spoke flows stop.** Each segment table (`prod`,
`nonprod`) now holds a blackhole route for every spoke CIDR of the other
segment. The spoke CIDR is `aws.network.spoke_attachments.<key>.cidr`, else
`aws.workload_environments.<key>.vpc_cidr`. Before, both segments
default-routed to the same inspection (or, on starter, egress) attachment,
whose table knows every spoke. A prod to nonprod flow was therefore routable,
and only the Network Firewall policy stopped it. In alert-only mode (and on
starter, through the NAT gateway) it passed. Such flows now drop at the
transit gateway, whatever the firewall policy.

What the plan shows on an existing estate with spokes: one
`aws_ec2_transit_gateway_route.segment_isolation["<table>|<spoke>"]`
(blackhole) per spoke and per other segment. Nothing is removed or replaced.
Spokes in the same segment, egress, the interface endpoints and on-premises
traffic do not change.

Find cross-segment flows before you apply:

1. Network Firewall flow logs (in the log archive): look for flows whose
   source is in a prod spoke CIDR and whose destination is in a nonprod spoke
   CIDR, or the reverse.
2. On starter (no firewall), use the VPC flow logs of the spokes: accepted
   flows between a prod spoke CIDR and a nonprod spoke CIDR.
3. List the blackholes the plan adds with the stage output
   `segment_isolation_routes` (in the plan, under the network-hub module).

If a workload needs a cross-segment flow: this is not supported, and there is
no switch to turn the blackholes off. Move the shared dependency to a
shared-services path that both segments may reach (for example the egress VPC
interface endpoints, or a service reached through the hub), or design a
deliberate, reviewed exception outside this module. Do not remove a spoke
`cidr` to bypass the isolation: the `segments_isolated` check warns about it.

#### The egress VPC routes on-premises prefixes to the VPN (aws-network)

With the VPN on, aws-network now routes the on-premises prefixes from the
egress VPC, so the Resolver endpoints can answer and forward to on-premises.
Before, these replies and forwards went to NAT.

What the plan shows on an existing estate with the VPN (only added routes,
nothing removed or replaced):

- One `aws_route.hub_to_tgw["egress-onprem-<az>-<prefix>"]` per AZ and per
  `vpn.onprem_cidrs` prefix in the egress VPC private route tables, to the
  transit gateway.
- One TGW route `shared:onprem:<prefix>` per prefix in the `shared` table, to
  the inspection attachment.
- A propagation of the egress attachment into the `inspection` table.

No working flow is interrupted: traffic from the egress VPC private tier to
these prefixes went to NAT and could not reach on-premises. If a prefix in
`vpn.onprem_cidrs` is reachable over the internet today (a public range), the
egress VPC now sends it to the VPN instead. Estates without the VPN plan no
change.

With BGP, `vpn.onprem_cidrs` now also sets these routes, because BGP routes
reach only the TGW `inspection` table, not VPC route tables. List at least the
on-premises resolver ranges there. A `check` warns when the VPN and the
Resolver endpoints are on and the list is empty.

With the VPN on, the aws-network plan now fails when a `vpn.onprem_cidrs`
prefix overlaps `top_cidr`, `inspection_cidr`, `egress_cidr` or a spoke
`cidr`, and the tfc-admin plan fails when it overlaps any AWS or GCP range in
`config/landing-zone.yaml`. Such a prefix would send AWS traffic to the VPN.
Before you upgrade, remove or narrow any overlapping prefix.

#### Access Analyzer in every enabled region (aws-security)

The external analyzer now exists in every `aws.enabled_regions` entry (the home
region keeps its address), and `enable_internal_access_analyzer` (default `true`)
adds the `ORGANIZATION_INTERNAL_ACCESS` analyzer in each region. These are NEW
resources on the upgrade apply, in the security-tooling account. Set
`aws_overrides.enable_internal_access_analyzer = false` to skip the internal ones.

#### AWS Config recorders move to an aws-organization StackSet

The workload roots no longer manage a Config recorder. `aws-organization`
deploys recorders org-wide: a service-managed StackSet, `org-config-recorders`,
covers every member account except security tooling, and the management account
gets a direct recorder. A new recorder SCP then limits who can change them.
Everything is behind flags that default to `false`, so nothing changes until
you follow the runbook.

**What changes on the next plan (no manual step):**

- **aws-workload-<env>**: `module.config_recorder` leaves state through a
  `removed` block with `destroy = false`. The live recorder, delivery channel
  and service-linked role stay in the account and keep recording. The plan must
  show no destroy.
- `config_role_arn` and `create_config_service_linked_role` (workload stage and
  root) are deprecated and ignored. A check warns while they are set. The
  workload `config_role_arn` output is now always null. All three are removed
  in v1.0.
- **securityhub-org** rejects `EC2.6` in `disabled_control_identifiers`.

**Manual steps (existing AWS estates):** follow
[`docs/runbooks/aws-config-recorder-migration.md`](docs/runbooks/aws-config-recorder-migration.md).

1. Upgrade the workload roots.
2. Apply aws-security.
3. Apply aws-organization with `enable_org_config_recorders = true` and
   `org_config_recorders_failure_tolerance_percentage = 100`.
4. Delete the legacy recorders with `scripts/aws-delete-legacy-recorders.sh`
   (break-glass, dry-run first).
5. Re-apply aws-organization with tolerance `0`.
6. Apply aws-organization with `enable_config_recorder_scp = true`.

A greenfield estate sets both flags to `true` once aws-security has applied
(`scripts/init-landing-zone.sh --aws-config-recorders true`). Until you
complete the migration, the accounts outside the workload roots (Infrastructure,
log archive, forensics, management) have no recorder, as before.

**Legacy removal in v1.0:** the workload `removed` block, the deprecated
workload inputs and output, and the flag-off path of the recorder SCP (the
recorder actions in `DenyWeakenSecurityServices`).

#### AWS management KMS access by key policy, not tags

`tfc-management-roles` no longer grants the aws-security apply role `kms:*` on
keys carrying `Workspace = aws-security` (a tag anyone with `kms:TagResource`
could plant). `CreateOwnedKeysOnly` stays unchanged (owner request tag required). The org trail's CloudWatch Logs CMK is instead managed through
its own key policy: a new `PipelineKeyManagement` statement
(`cloudwatch_logs_kms_key_manager_arns`, defaulting to the
`tfc-mgmt-aws-security-apply` role) grants describe/get/list, rotation,
description, tags and aliases, plus data-key use (`PipelineKeyUseViaServices`,
`kms:ViaService` SNS and Logs only). The account-root `kms:*` statement is kept.

**Manual step for existing estates (before applying the new
`tfc-management-roles`):** the pipeline's `kms:PutKeyPolicy` is denied, so the
new statement must be added once, by a break-glass principal (the account root
or an administrator in the management account). Without it, the next
aws-security plan/apply gets AccessDenied on the key. Substitute your values:

```sh
KEY_ID=$(aws kms describe-key --key-id alias/<trail_name>-cloudwatch --query KeyMetadata.KeyId --output text)
aws kms get-key-policy --key-id "$KEY_ID" --policy-name default --query Policy --output text > policy.json
# Edit policy.json: append these statements to "Statement" (keep the existing ones):
#   {"Sid":"PipelineKeyManagement","Effect":"Allow",
#    "Principal":{"AWS":"arn:aws:iam::<MGMT_ACCOUNT_ID>:role/tfc-mgmt-aws-security-apply"},
#    "Action":["kms:Describe*","kms:Get*","kms:List*","kms:EnableKeyRotation",
#              "kms:UpdateKeyDescription","kms:TagResource","kms:UntagResource",
#              "kms:CreateAlias","kms:UpdateAlias","kms:DeleteAlias"],
#    "Resource":"*"}
#   {"Sid":"PipelineKeyUseViaServices","Effect":"Allow",
#    "Principal":{"AWS":"arn:aws:iam::<MGMT_ACCOUNT_ID>:role/tfc-mgmt-aws-security-apply"},
#    "Action":["kms:GenerateDataKey*","kms:Decrypt"],"Resource":"*",
#    "Condition":{"StringEquals":{"kms:ViaService":
#      ["sns.<REGION>.amazonaws.com","logs.<REGION>.amazonaws.com"]}}}
aws kms put-key-policy --key-id "$KEY_ID" --policy-name default --policy file://policy.json
```

Then upgrade `tfc-management-roles`, and confirm aws-security plans with no
changes to the key policy. Fresh estates need nothing.

#### aws-security cannot disable org detection; org-owned guard alerts

`tfc-management-roles` drops these actions from the aws-security apply role:
`Disable*AdminAccount`, `fms:DisassociateAdminAccount`,
`organizations:DisableAWSServiceAccess`,
`DeregisterDelegatedAdministrator` and `cloudwatch:DeleteAlarms`. It now
denies trail untagging and resource-policy edits, CIS-alarm deletion and
disabling, and trail log-group, log-stream, metric-filter and retention deletion.
`aws-organization` creates `org-guard-alerts` in us-east-1 of the management
account: a CMK, an SNS topic and an EventBridge rule. It also creates one
forwarding rule per other `aws.enabled_regions` region, plus the
`org-guard-alerts-forwarder` IAM role.

- **No manual step for a routine upgrade.** Apply `aws-organization` first; it
  only adds resources. Optionally set `aws.guard_alert_emails`, then confirm
  each subscription email.
- **A plan that now replaces a CIS alarm or metric filter fails** with
  AccessDenied on the delete. Run that apply as break-glass or the phase-0
  role.
- **Removing a tag key from the org trail needs break-glass.**
  `cloudtrail:RemoveTags` is denied, so a plan that drops a tag from the trail
  (for example, a removed `default_tags` key) fails with AccessDenied. Changing
  a tag's value still works.
- **Destroying aws-security** (or removing a delegated admin) needs
  `enable_security_service_teardown = true` on `aws-organization`. See
  `docs/runbooks/aws-teardown.md`.

#### Production egress fails closed (aws-network)

`aws-network` now fails the plan when the profile is `production` and an AWS
workload environment sets `is_production: true` unless
unmatched egress is dropped and a domain allowlist is set. Before upgrading,
set in `config/landing-zone.yaml` (seed in `config/landing-zone.example.yaml`):

```yaml
aws:
  network:
    egress_domain_allowlist: [.amazonaws.com, .github.com, .githubusercontent.com, .terraform.io]
    stateful_default_actions: [aws:drop_established, aws:alert_established]
```

Extend the allowlist with every domain your workloads reach first: all other
HTTP/TLS egress is dropped once applied. To keep alert-only inspection while
you build the list, set `aws.network.egress_alert_only_waived: true` (an
explicit, reviewable waiver). Starter-profile estates are unaffected.

#### aws-workload: exact exec-role ARNs in the workload CMK key policy (in-place)

The `AppTaskExecutionRolesDecrypt` statement of the workload CMK
(`aws_kms_key.workload`, created when `kms_key_arn = ""`) no longer matches
`role/<environment>-*-exec`. It lists the exact ARN of each declared service's
task execution role (`arn:<partition>:iam::<account>:role/<environment>-<service>-exec`)
under `ArnEquals aws:PrincipalArn`, and is omitted when `services = {}`. The
next plan shows an **in-place** update of the key policy; this is expected. The
key is not replaced or moved. A role whose name matches the old wildcard but is
not an app-services execution role loses kms:Decrypt on the key: grant it
explicitly if you relied on that. A supplied `kms_key_arn` is unaffected.

#### aws-network: Site-to-Site VPN on the TGW (opt-in)

`aws.network.vpn.enabled` adds a Site-to-Site VPN attached to the Transit
Gateway, with a new `hybrid` TGW route table that default-routes to the
inspection VPC. On-premises routes propagate into the `inspection` table only,
so on-premises traffic to and from a spoke is routed through inspection in both
directions **once that spoke is wired** with `aws.network.spoke_attachments`
(see the next entry); an unwired spoke has no route to or from on-premises. Tunnel pre-shared
keys are stored in Secrets Manager (`vpn_preshared_key_arn` output), not in
state, unless you set `preshared_key_storage = "Standard"`. Off by default: no
plan change when unset.

#### aws-network: workload spoke routing wired from config (fixes unrouted spokes)

**Before this release no workload spoke was routed.** `aws-workload-<env>`
creates its TGW attachment with default association/propagation off, and nothing
accepted, associated or propagated it, so spokes had no egress, no egress
replies and no on-premises path. New `aws.network.spoke_attachments` (aws-network
variable `spoke_attachments`, default empty: no plan change) lists each spoke:

```yaml
aws:
  network:
    spoke_attachments:
      dev:  {attachment_id: tgw-attach-..., segment: nonprod}
      prod: {attachment_id: tgw-attach-..., segment: prod}
```

**Manual steps (estates with spokes):**

1. Read each `aws-workload-<env>` output `tgw_attachment_id` (new root output;
   or `aws ec2 describe-transit-gateway-attachments` in the network account).
2. Add it under `aws.network.spoke_attachments` with the spoke's segment. If
   the attachment is already `available` (someone accepted it by hand), set
   `accept: false`; a `pendingAcceptance` one keeps the default `accept: true`.
   **Never flip `accept` (true to false or back) on a spoke Terraform already
   manages, and never rename its key without a `moved` block:** destroying the
   accepter deletes the spoke's attachment, which cuts the spoke off
   (`destroy_guard` blocks it). If someone also associated it by hand, disassociate it first or import the
   association (`terraform import 'module.aws_network_hub.aws_ec2_transit_gateway_route_table_association.spoke["<env>"]' <tgw-rtb-id>_<tgw-attach-id>`).
3. Apply `aws-network`. The plan is additive only: per spoke an accepter
   (when `accept`), an association and a propagation into the inspection table,
   plus two hub routes once (`inspection 0.0.0.0/0 → egress`,
   `shared <top_cidr> → inspection`).

A new spoke needs the same step after its first workload apply
(`docs/runbooks/aws-add-account.md`). With `enable_network_firewall = false`
(the `starter` profile) spokes egress through NAT without inspection; see
"Starter spokes egress through NAT; starter rejects the VPN".

#### AWS org trail managed by the CloudTrail delegated administrator (opt-in)

New `aws.enable_cloudtrail_delegated_admin` (default `false`: no change on
upgrade). When on, `aws-organization` registers security tooling with
`aws_cloudtrail_organization_delegated_admin_account` and removes every trail
write (`OrganizationTrailOnly`, the delivery-role PassRole, and the
`cloudtrail.amazonaws.com` delegation) from `tfc-mgmt-aws-security-apply`;
`aws-security` creates a new organization trail, `org-trail-delegated`, with the
security-tooling provider, with its CloudWatch Logs group, delivery role, CMK,
CIS alarms and topic in security tooling. The deny-tamper SCP then applies to
the trail. New keys: `aws.enable_cloudtrail_delegated_admin`,
`aws.create_management_trail`, `aws.adopt.cloudtrail_delegated_admin_account_id`
(aws-organization), and `aws_overrides.cloudtrail_delegated_admin_trail_name`.

**Manual steps (existing estates), in order** — follow
`docs/runbooks/aws-cloudtrail-delegated-admin-migration.md`:

1. Set `aws.enable_cloudtrail_delegated_admin: true` and
   `aws.adopt.cloudtrail_delegated_admin_account_id: "<security-tooling ID>"`.
   Apply `aws-organization` (expect one import and an in-place policy update).
2. Before `aws-security` applies:
   `terraform state rm 'module.aws_security.module.delegated_admin.aws_organizations_delegated_administrator.this["cloudtrail.amazonaws.com"]'`.
   Apply `aws-security`: creates only; `module.cloudtrail[0]` unchanged.
3. Verify delivery of `org-trail-delegated`, overlap at least one hour.
4. Delete `org-trail` with break-glass, then
   `terraform state rm 'module.aws_security.module.cloudtrail[0]'` and set
   `aws.create_management_trail: false` together. Retire the old CIS alarms.

Greenfield estates that start with the flag on also set
`aws.create_management_trail: false` and no adopt ID. The scaffolder does not
turn it on until the sandbox proves the runbook.

**v1.0 legacy removal:** the management-account trail mode is removed:
`enable_cloudtrail_delegated_admin = false`, `module.cloudtrail` in the
aws-security stage (retired with
`removed { from = module.cloudtrail  lifecycle { destroy = false } }`),
`create_management_trail`, the `OrganizationTrailOnly` /
`PassTrailDeliveryRoleToCloudTrail` grants, the generic
`cloudtrail.amazonaws.com` registration (`register_cloudtrail_admin`) and
`create_org_trail_delivery_role`.

With the flag on, aws-organization's `org-guard-alerts` event pattern changes in
place (it also alerts on any trail change made from the management account), and
aws-security adds `sec-notify-org-trail-tamper` in security tooling.


#### aws-security: the security-tooling CMK grants EventBridge (key-policy update)

The security-tooling CMK, which encrypts the security-notifications SNS topic,
now grants `events.amazonaws.com` (scoped to the account by `aws:SourceAccount`).
Before this, EventBridge could not publish the `sec-notify-*` alerts to the
encrypted topic, so those deliveries failed. The next aws-security plan shows an
in-place key-policy update. Where the key policy is protected against pipeline
edits, apply it with break-glass. After the apply, check that a test alert
arrives.

#### aws-organization: EC2 Allowed AMIs in the declarative EC2 policy (audit mode)

The `declarative-ec2-baseline` declarative policy, attached at the org root, now
carries `allowed_images_settings` through the new `ec2_allowed_images` input
(default: `state = "audit_mode"`, providers `["amazon"]`). The first apply updates
that policy in place. Audit mode blocks nothing: it only flags AMIs outside the
allowed providers. The root policy does take over Allowed AMIs from the member
accounts, though. Any account-level settings are overridden, and the
Enable/Replace/Disable API calls are locked out in member accounts. Review the
audit findings before you set `state = "enabled"`. Set `state = "unmanaged"` to
leave the setting out of the policy.

### GCP

#### gcp-projects creates projects under the folder name (gcp-projects)

**Who:** forks that pass the gcp-organization contract to gcp-projects by hand
(`organization_contract`, or `gcp.contracts.organization` in
`config/landing-zone.yaml`). A contract read from the gcp-organization
workspace already has the right shape.
**What changes:** gcp-projects now creates projects and makes its folder grants
on `folders.<key>.name` (`folders/<number>`), not on `folders.<key>.id`, which
gcp-organization emits as the bare folder number. Before, every gcp-projects
plan from the workspace contract failed on the project parent. A
`organization_contract` variable whose folder `name` is not `folders/<number>`
now fails the plan with an error that names the field. In the config file,
`id` may be the bare number or `folders/<number>`, and `name` is derived from
`id` when you leave it out. `environment_config.<env>.folder_id` in the
gcp-projects contract is now always the bare number; gcp-workload accepts
either form, so its plan does not change.

Steps:

1. If you pass `organization_contract` by variable, set each folder's `name`
   to `folders/<number>` and `id` to the bare number.

#### Cloud Run uses the egress proxy when it is on (gcp-workload, app-services, breaking, ARC-H1)

**Who:** every `gcp-workload-<env>` with the egress proxy on
(`gcp.environments.<env>.egress_proxy: true` or `enable_egress_proxy`) and at
least one app service or job. Environments with the proxy off see no change.
**What changes:** `vpc_egress` now defaults to null. With the proxy on, null
means `ALL_TRAFFIC`; with it off, null means `PRIVATE_RANGES_ONLY`, as before.
With the proxy on, every Cloud Run service and job also gets `HTTPS_PROXY`,
`HTTP_PROXY` and `NO_PROXY` (and the lower-case forms) for
`http://<PSC endpoint>:<port>`. The plan shows an in-place update of each
service and job (a new revision). Before, Cloud Run sent internet traffic on
its own path and skipped the proxy.
**Breaking:** a production environment with the proxy on now fails the plan
when a service sets `vpc_egress: PRIVATE_RANGES_ONLY`. Remove the key (the
default is then `ALL_TRAFFIC`) or set `ALL_TRAFFIC`. To keep a service off the
proxy, turn the proxy off for the environment, which needs
`production_egress_proxy_waiver`.

Steps:

1. Apply gcp-network-hub once (a refresh is enough). Its contract gains
   `hub_network.egress_proxy_port`, the proxy's first port. Until then the
   environments use 443, the hub default. If you set `gcp.contracts.network_hub`
   in `config/landing-zone.yaml` and the hub proxy listens on another port, add
   `egress_proxy_port` there.
2. Check that each service's HTTP clients honour the proxy variables, and that
   every FQDN a service calls is in `secure_web_proxy.allowed_fqdns`. With the
   proxy on, the private tier has no Cloud NAT, so a call the proxy does not
   carry fails.
   - Node.js: the stage injects `NODE_USE_ENV_PROXY=1`. Node.js v24.0.0 and
     later (and v22.21.0 and later) then route `fetch()` and
     `http(s).request` through the proxy. Older Node.js ignores the variables;
     use an agent library or upgrade.
   - JVM: the JVM ignores `HTTPS_PROXY`. Start it with
     `-Dhttps.proxyHost=<address> -Dhttps.proxyPort=<port>`,
     `-Dhttp.proxyHost` / `-Dhttp.proxyPort`, and `-Dhttp.nonProxyHosts`
     (pipe-separated, `*` wildcards such as `*.googleapis.com|*.run.app`), for
     example through `JAVA_TOOL_OPTIONS` in the service's `env_vars`. The stage
     does not set these.
   - Google domains outside `googleapis.com` (for example `*.pkg.dev`,
     `gcr.io`, `accounts.google.com`, `*.firebaseio.com`, `*.appspot.com`) go to
     the proxy: add them to `secure_web_proxy.allowed_fqdns`, or to a service's
     `no_proxy` when Private Google Access serves them.
3. To extend `NO_PROXY` (for example with an internal host name), set the
   service's `no_proxy` list, or `NO_PROXY` / `no_proxy` in its `env_vars`.
   Both are appended to the defaults, which always stay (the
   `egress_proxy_settings` output of the app-services stage lists them).

#### An environment outside the hub region cannot use the hub egress proxy (net-spoke, ARC-H2)

**Who:** a `gcp-workload-<env>` with the egress proxy on whose region differs
from the hub Secure Web Proxy region. **What changes:** the plan fails with a
message that names both regions. Google creates a Private Service Connect
endpoint only in the region of the published service, so this configuration
already failed at apply. Keep the proxy off for that environment; as production
it needs `production_egress_proxy_waiver`.

#### The environment perimeter now holds the service-team projects (gcp-workload, breaking, ARC-C1)

**Who:** every `gcp-workload-<env>` with a VPC-SC perimeter and at least one
`service_teams` entry.
**What changes:** the `<env>_perimeter` perimeter lists the host project and
every service-team project. Before, it listed the host project only. The plan
shows an in-place update of the perimeter. No input changes, and no resource is
replaced. Service-team projects now wait for the spoke network only, not for
all of the spoke, so the first apply of a new team may create its project
earlier in the run.

**Breaking (enforced perimeters):** an enforced perimeter can now block a call
between a team project and a caller or resource outside it, such as a CMEK key,
an image registry or an app-deploy WIF identity, until you add a rule for it. A
dry-run perimeter blocks nothing.

- **Dry-run perimeter** (the default outside production): only the dry-run
  spec changes. Nothing is blocked. Read the violation logs for the team
  projects before you enforce.
- **Enforced perimeter**: calls between a team project and anything outside the
  perimeter are now checked, and can be blocked. Check these before you apply:
  a CMEK key in a project outside the perimeter
  (`database.encryption_key_name`, `app_platform.artifact_registry_kms_key_name`),
  an image registry outside the perimeter, an app-deploy WIF identity, and any
  other caller outside Google Cloud. Add a `vpc_sc_egress_policies` or
  `vpc_sc_ingress_policies` rule for each one that is legitimate.

Steps for an enforced production environment:

1. Apply with `vpc_sc_enable_dry_run = true` and a short
   `production_vpc_sc_dry_run_waiver` `{reason, expires}` in
   `config/tfc-workspaces.yaml`. This also leaves the host project unenforced
   during the soak, because the enforced status and the dry-run spec share one
   project list, so keep the soak short.
2. Let real traffic run. Read the dry-run violation logs
   (`protoPayload.metadata.dryRun = true`) for the team projects. Add a rule for
   each legitimate call.
3. Remove the waiver, set `vpc_sc_enable_dry_run = false` and apply.

A regulated environment (`compliance_class: regulated`) refuses the waiver.
Run steps 1 and 2 on a non-regulated environment with the same services first,
add the same rules to the regulated environment, then apply it.

#### Production networks pin their zones (gcp-workload, gcp-network-hub, breaking, IAC-1)

**Breaking: a production plan that passed before now fails.** Each spoke, hub and DNS anchor VPC
has one subnet per zone and tier. Subnet `i` of a tier takes the `i`-th CIDR of the block, so the
zone list fixes the CIDRs. That list came from the zones GCP returns for the region. When GCP
returns a different list (a new zone, or another order), the plan re-derives the CIDRs and
replaces subnets in use. Now:

- `gcp-workload-<env>` fails the plan for a production environment
  (`environment_config.<env>.is_production = true`) until `gcp.environments.<env>.zones` (or the
  `zones` variable) is set. The guard is `terraform_data.production_network_guard`.
- `gcp-network-hub` fails the plan when any `gcp.environments` entry is production until
  `gcp.network.zones` (or the `hub_zones` variable) is set. One list sets the hub VPC and the DNS
  anchor VPC; both are in `org.regions.gcp`. The guard is
  `terraform_data.production_hub_zones_guard`.

A non-production environment may still leave its zones unset.

**Existing network: keep the zones it has, in the same order.** Do not take the order of
`gcloud compute zones list`; take it from the subnets, so the CIDRs do not change:

```sh
gcloud compute networks subnets list --project=<host-project> \
  --filter="network~/<vpc-name>$ AND name~-public-" \
  --format="value(ipCidrRange,name)" | sort -V
```

Sort the CIDRs as numbers (`sort -V` above), not as text: `gcloud --sort-by=ipCidrRange` sorts
text, which puts `x.y.z.128/26` before `x.y.z.64/26`. The zone is the end of each subnet name
(`<vpc>-public-<zone>`). Skip additional-region subnets: their name ends in a region, not a
zone. List the zones in the order of their CIDRs, lowest first (for a `/16` block: `x.y.0.0/24`,
then `x.y.1.0/24`, and so on).

Cross-check: the google provider's `google_compute_zones` data source sorts the zone names before
it returns them (`sort.Strings` in `data_source_google_compute_zones.go`, checked on the
provider's main branch on 2026-11-13). So a network built from discovered zones normally has its
zones in alphabetical order. If the CIDR order you found is not alphabetical, find out why (for
example, an older provider or zones pinned earlier) before you set the list.

Do the same for the hub (`hub-vpc-core` in the hub project) and the DNS anchor (`dns-vpc-core` in the DNS project). The
hub and DNS anchor take one list, so they must have the same zones in the same order. If they
differ, keep the hub's order and plan: the DNS anchor holds no workloads, but its subnets are then
replaced, so review that plan first. Then set, for example:

```yaml
gcp:
  network:
    zones: [europe-west2-a, europe-west2-b, europe-west2-c]
  environments:
    prod:
      zones: [europe-west2-a, europe-west2-b, europe-west2-c]
```

Plan each workspace. The plan must show no subnet change. If it does, the order is wrong.

**New estate:** the scaffolder writes `<region>-a`, `-b` and `-c` (for `us-east1` and
`europe-west1`, which have no `-a` zone: `-b`, `-c` and `-d`) and reports them as derived, not
verified. Check them with `gcloud compute zones list --filter=region:<region>` before the first
apply.

#### Network and edge logs go to the audit bucket in regulated and framework estates; a legacy audit sink identity needs a grant first (gcp-organization, CMP-02)

**Behaviour change.** Nothing existing changes or is replaced. It is not breaking unless
`org-audit-sink` still writes as a legacy identity: then the apply fails until you grant it (see
**Legacy audit sink identity** below). When any
`gcp.environments` entry is `compliance_class: regulated`, or `compliance.frameworks` lists any
framework, the next `gcp-organization` plan adds one resource: the aggregated org sink
`org-network-logs`. It copies firewall rule logs, Cloud NAT logs, load balancer request logs (with
the Cloud Armor verdict), Secure Web Proxy request logs and Cloud NGFW threat logs from every project
into the GCS audit bucket.

No new IAM grant is needed. Since 2023-05-22 Cloud Logging uses one service account for all sinks
in a resource, so the new sink writes as the same identity as `org-audit-sink`, which already holds
`roles/storage.objectCreator` on the audit bucket.

The logs then have the audit bucket's retention (`audit_log_retention_days`, at least the
framework floor) and, when `gcp.enable_audit_bucket_lock` is on, its locked retention. With the
lock they cannot be deleted before that period ends, so the storage cost is committed. Read the
cost note in [`docs/architecture/gcp-landing-zone.md`](docs/architecture/gcp-landing-zone.md#cost-of-the-baseline)
and `docs/compliance/control-matrix.md` LOG-06.

**Legacy audit sink identity.** If `org-audit-sink` was created before 2023-05-22, it keeps a
dedicated legacy service account, and the new sink gets the org's shared Logging service account.
Only the legacy account holds `roles/storage.objectCreator` on the audit bucket, so the new sink
cannot deliver. Check before you apply: compare the writer identity of `org-audit-sink` with the
org's shared Logging service account (shown by `gcloud logging sinks describe` for any org sink
created on or after 2023-05-22). The list below shows every org sink and its identity:

```sh
gcloud logging sinks list --organization=<ORG_ID> --format='table(name, writerIdentity)'
```

If they differ:

1. Grant `roles/storage.objectCreator` on the audit bucket to the shared identity as break-glass.
   Admin containment denies `setIamPolicy` on the audit bucket to the automation identity.
2. Set `gcp.network_log_writer_granted: true` in `config/landing-zone.yaml` (or
   `gcp_overrides.network_log_writer_granted = true`).
3. Apply `gcp-organization`.

Or set `gcp.enable_network_log_export: false`.

If you apply without the grant, the apply creates `org-network-logs` and then fails on its
postcondition, which names both identities. Terraform does not undo the create, and it does not
taint the sink (checked with Terraform 1.17.1): the sink stays in state, and its writes to the
bucket fail until the grant exists, so those logs are not exported in that time. Every later plan
fails on the same postcondition. Recover with the three steps above; the next apply then changes
nothing on the sink. To back out instead, set `gcp.enable_network_log_export: false`; deleting the
sink needs break-glass under admin containment and a `destroy_guard` override (see below).

Other steps:

1. If the audit project is in an enforced VPC-SC perimeter, the ingress rule that admits the audit
   sink's writer already admits the shared identity. A legacy identity needs the shared one added.
2. To keep the old behaviour, set `gcp.enable_network_log_export: false` in
   `config/landing-zone.yaml` (or `gcp_overrides.enable_network_log_export = false`). Set it to
   `true` to turn the export on for any other estate.

With admin containment on, the org IAM deny policy blocks sink update and delete for everyone but
break-glass. Turning the export off after it was applied, or changing its filter, then needs a
break-glass apply. Deleting the sink also trips the `destroy_guard` policy
(`google_logging_organization_sink`), so the security team must override that run. Deleting it never
removes the shared identity or its grant.

#### The audit store waiver names a reason and expires (gcp-organization, breaking, CMP-05)

**Breaking: `gcp.audit_store_waived` is removed.** Any value of it (also `false`) now fails the
`gcp-organization` plan and `make config-check`, and both name the new key. Replace it with an
object:

```yaml
gcp:
  audit_store_waiver:
    reason: Logging project pending; risk register entry R-12
    expires: "2027-03-31"
```

`reason` must not be empty. `expires` must be a real `YYYY-MM-DD` date; quote it, so YAML keeps it
a string. The waiver lets a regulated estate (and the production-profile warning) pass without
`gcp.logging_project_id` and `gcp.enable_audit_bucket_lock` through that day (UTC). After it, the
plan fails again, the same rule as `production_vpc_sc_dry_run_waiver`. If you had
`audit_store_waived: false`, delete the line. If you had `true`, write the object with the date by
which the hardened audit store will exist.

#### Production egress needs the hub proxy or a waiver (gcp-workload, breaking, ARC-4)

**Breaking: a production `gcp-workload-<env>` plan that passed before now fails.** Without the hub
Secure Web Proxy the private tier leaves through Cloud NAT with no destination allowlist.
`terraform_data.production_network_guard` now fails the plan for a production environment
(`environment_config.<env>.is_production = true`) unless one of these is true:

1. **The egress proxy is on.** Enable `secure_web_proxy` on `gcp-network-hub` (with the host
   project as a consumer) and apply it, then set `gcp.environments.<env>.egress_proxy: true` (or
   `enable_egress_proxy`). The private tier then leaves Cloud NAT, so set `HTTPS_PROXY` in the
   workloads and list every destination in the proxy allowlist first. The proxy is PREVIEW: prove
   it in the sandbox (`docs/known-gaps.md`).
2. **A time-boxed waiver.** Add it for that workspace in `config/tfc-workspaces.yaml`
   (its CODEOWNERS line lists the platform and the security team, so either team's approval satisfies it) and re-apply tfc-admin:

   ```yaml
   workspaces:
     gcp-workload-prod:
       production_egress_proxy_waiver:
         reason: Hub egress proxy not yet proven in the sandbox
         expires: "2026-12-31"
   ```

   `reason` must not be empty and `expires` must be a real `YYYY-MM-DD` date. The waiver stops
   working after that date (UTC), and the plan fails again.

A standalone environment (`enable_network_hub = false`) cannot use the proxy, so in production it
needs the waiver. The scaffolder writes neither choice. The guard has no cloud side effect.

#### CMEK for regulated Cloud SQL (gcp-workload, CMP-12)

**Who:** forks with a `compliance_class: regulated` environment whose app
services declare a `database`. Nothing changes for a standard environment.

**What changes:** in a regulated `gcp-workload-<env>`, every app-service
database must set `database.encryption_key_name` and keep deletion protection
on, or the plan fails and names the instance. The new inputs are
`require_cmek` (`modules/gcp/data/cloud-sql`), `require_database_cmek`
(app-services stage) and `app_platform.require_database_cmek` (environment
stage); `envs/gcp/workload` sets them from the class.

`encryption_key_name` is ForceNew on `google_sql_database_instance` (google
provider 8.x, `resource_sql_database_instance.go`), and Google does not let you
enable CMEK on an existing instance
([Cloud SQL CMEK](https://docs.cloud.google.com/sql/docs/postgres/cmek)). So the
landing zone never adds a key to an existing database for you: adding one would
replace the instance and lose its data. The deletion guard makes such a plan
fail too.

**New database:** create a Cloud KMS key in the instance region (a
multi-region or global key does not work), grant the Cloud SQL service agent
access to it (and the Backup and DR service agent, because the regulated class
turns the vault on), set `database.encryption_key_name`, then apply.

**Existing database without a key:** a regulated plan fails while the old
database is in the config, so migrate it **before** you set
`compliance_class: regulated` on the environment. `compliance_class` is new in
this release, so no released estate has a regulated environment yet.

The app-services stage names the instance after the service, so the new
CMEK instance replaces the old one under the same name. Plan a maintenance
window, and keep your own copy of the data, because the replacement deletes
the old instance. Cloning does not help: a clone keeps the source instance's
key.

1. Create the key as above.
2. Stop writes. Export every database of the instance to a Cloud Storage
   bucket that is itself CMEK-encrypted (`gcloud sql export sql`), and check
   that the export is complete.
3. Lift the guard for this one database: `terraform state rm` its
   `terraform_data.deletion_protection_guard[0]`, set
   `database.enable_deletion_protection: false` and apply. This apply only
   turns the instance's own `deletion_protection` off; the provider refuses to
   delete an instance while it is on.
4. Set `database.encryption_key_name`. Read the plan: it must replace only
   this instance. Apply.
5. Import the export into the new instance (`gcloud sql import sql`) and
   check the application.
6. Set `database.enable_deletion_protection` back to true (or remove the
   line) and apply.
7. Set `compliance_class: regulated`.

A policy set with the `destroy_guard` policy stops the step 4 run until the
security team overrides it; record the override.

#### `audit_key_protection_level` (gcp-organization, CMP-12)

`gcp.audit_key_protection_level` (or `gcp_overrides.audit_key_protection_level`)
sets the Cloud KMS protection level of the two audit CMEK keys (`audit-logs`,
`audit-analytics`): `SOFTWARE` (default, no change) or `HSM` (Cloud HSM, FIPS
140-2 Level 3). The billing and SCC keys stay `SOFTWARE`.

**Changing it on existing audit keys fails the plan (keys are never destroyed).**
`protection_level` lives on the key's version template, which the google
provider marks ForceNew (`resource_kms_crypto_key.go`), and the KMS module sets
`prevent_destroy`. Use it for a new estate or a new logging project only: set it
in the same change that first sets `gcp.logging_project_id`. Cloud HSM key
versions cost more than software ones (Google lists USD 0.06 per software key
version and USD 1.00 to 2.50 per HSM key version per month,
[Cloud KMS overview](https://docs.cloud.google.com/kms/docs/key-management-service)).

#### Cloud SQL backups stay in the instance region; Backup and DR vault for regulated environments (gcp-workload, gcp-bootstrap, gcp-organization, breaking, CMP-8)

**Cloud SQL backups stay in the instance region.** `backup_location = null` (`modules/gcp/data/cloud-sql`, and `database.backup_location` of an app service) now means the instance region, not Cloud SQL's nearest multi-region. Before, an instance in `europe-west2` wrote its backups to the `eu` multi-region, which can be outside `gcp.allowed_regions`; Cloud SQL backups fail when they land in a region the organization policy does not allow ([Create and manage on-demand and automatic backups](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/backing-up)). The next `gcp-workload-<env>` plan shows an in-place update of `settings.backup_configuration.location` on every app-service database that does not set `backup_location`. Existing backups stay where they are; new ones land in the region. Set `backup_location: eu` (or `us`, `asia`) on the service's `database` to keep multi-region backups.

**Backup and DR vault.** A `compliance_class: regulated` environment now gets a Backup and DR vault in its host project with a daily plan for every app-service database (BCK-07, PREVIEW). Any other environment can opt in with `gcp.environments.<env>.backup_vault.enabled: true` or `enable_backup_vault = true`. The plan replaces the instance's own backup schedule and retention (Cloud SQL enhanced backups). Every backup is immutable for `enforced_retention_days` (default 35). The vault sets no retention lock unless `gcp.environments.<env>.backup_vault.lock_effective_time` is set; that lock is irreversible.

Apply order for an estate that uses the vault:

1. `gcp-bootstrap`: the workload folder roles gain `roles/backupdr.admin` (apply) and `roles/backupdr.viewer` (plan). `roles/backupdr.admin` is non-delegable: projects-apply cannot grant it.
2. `gcp-organization`: grants `roles/backupdr.admin` to each workload apply SA on its environment folder.
3. `gcp-projects`: grants `roles/backupdr.viewer` to the workload plan SAs through the delegated folder IAM.
4. `gcp-workload-<env>`.

A regulated environment fails the plan with `enable_backup_vault = false`.

#### TLS 1.2 minimum on public ingress and Google APIs (gcp-workload, gcp-organization, breaking, CMP-5)

**Breaking for old clients.** Each `public_ingress` load balancer (`modules/gcp/network/app-ingress`) now gets a new SSL policy, `<env>-<service>-tls`: profile `MODERN`, minimum TLS 1.2. Before, the HTTPS proxy had no SSL policy, so Google used `COMPATIBLE` with a TLS 1.0 minimum ([SSL policies overview](https://docs.cloud.google.com/load-balancing/docs/ssl-policies-concepts)). The first `gcp-workload-<env>` apply creates the policy and updates the proxy in place. After it:

- clients that only speak TLS 1.0 or 1.1 can no longer connect (for example Internet Explorer 10 and older with default settings, Android 4.4 and older apps that do not turn TLS 1.2 on, Java 6, Java 7 clients on the TLS 1.0 default, and old embedded devices);
- TLS 1.2 clients that offer only non-ECDHE RSA key exchange or 3DES cipher suites fail the handshake, because `MODERN` drops the cipher suites only `COMPATIBLE` allows.

Check your load balancer logs or client inventory before you apply. A caller that passes `ssl_policy_id` keeps its own policy. `min_tls_version = "TLS_1_3"` with `ssl_policy_profile = "RESTRICTED"` raises the floor further.

The production profile (`org.profile: production`, the default) also sets the org policy `gcp.restrictTLSVersion` with denied values `TLS_VERSION_1` and `TLS_VERSION_1_1` ([Restrict TLS versions](https://docs.cloud.google.com/assured-workloads/docs/restrict-tls-versions)). The first `gcp-organization` apply creates it. Google Cloud resource APIs served through the Google Front End then refuse TLS 1.0 and 1.1; current Google client libraries, the Cloud SDK and Terraform providers use TLS 1.2 or later. It does not cover Cloud Run, App Engine, Cloud Run functions, Apigee, Private Service Connect or custom domains. Opt out with `gcp_overrides.restrict_tls_versions = false`. The starter profile does not set it unless `gcp_overrides.restrict_tls_versions = true`.

#### TLS 1.2 minimum on the cdn and internal-lb modules (breaking)

**Who:** callers of `modules/gcp/network/cdn`, and callers of `modules/gcp/network/internal-lb` with `is_l7 = true` and `enable_ssl = true`. No root or stage in this repository calls them.

**What changes:** each module now creates an SSL policy (`<name>-tls`, `<lb_name>-tls` for `cdn`) with profile `MODERN` and a TLS 1.2 minimum, and sets it on its HTTPS proxy. `cdn` creates a global `google_compute_ssl_policy`; `internal-lb` creates a `google_compute_region_ssl_policy` in `region`. Before, the proxy had no SSL policy, so Google used `COMPATIBLE` with a TLS 1.0 minimum ([SSL policies overview](https://docs.cloud.google.com/load-balancing/docs/ssl-policies-concepts)). The next apply creates the policy and updates the proxy in place. After it, clients that only speak TLS 1.0 or 1.1 can no longer connect, and TLS 1.2 clients that offer only cipher suites outside `MODERN` fail the handshake.

**What to do:** check your load balancer logs or client inventory before you apply. To keep your own policy, pass `ssl_policy_id`. To raise the floor, set `min_tls_version = "TLS_1_3"` with `ssl_policy_profile = "RESTRICTED"`.

#### Regulated environments require a hardened audit store (gcp-organization, CMP-4)

Nothing changes for an estate without `compliance_class: regulated`. Setting `compliance_class: regulated` on a `gcp.environments` entry fails the `gcp-organization` plan until `gcp.logging_project_id`, `gcp.logging_project_number` and `gcp.enable_audit_bucket_lock: true` are set, or an unexpired `gcp.audit_store_waiver` (see the CMP-05 entry above). The logging project must not be the admin project. The lock is irreversible. The three keys are new in `config/landing-zone.yaml`; `gcp_overrides.logging_project_id`, `gcp_overrides.logging_project_number` and `gcp_overrides.enable_audit_bucket_lock` still win over them.

Two new plan warnings (they never fail the plan): the production profile warns when an `is_production` environment exists and the audit store is not hardened (or waived), and the plan warns when the logging project sits in a folder.

Moving an existing estate to a logging project is a new audit store, not a move:

- The audit keyring and keys (`<prefix>-org-cmek` keys `audit-logs` and `audit-analytics`) leave the stage's key map. The KMS module sets `prevent_destroy` and GCP never deletes a key, so first remove them from the `gcp-organization` state (`terraform state rm` on `module.organization.module.cmek.google_kms_crypto_key.keys["audit-logs"]` and `["audit-analytics"]`, and their `key_iam` members). They stay in the admin project; destroy their key versions only after every object they encrypt has expired.
- The audit bucket, access-log bucket, BigQuery audit dataset, Log Analytics bucket and control-plane alerts are recreated in the logging project, and the org sinks are pointed at them. Plan shows them as replaced. A bucket you locked earlier cannot be deleted before its retention ends (GCS refuses the delete), and `destroy_guard` stops the run. Remove the old buckets and dataset from the state (`terraform state rm`) so the plan creates the new ones and leaves the old ones in place, read-only, until their retention ends. Then delete them by hand.
- Logs written before the switch stay in the old bucket. Keep it, and its CMEK keys enabled, for the full retention period. Auditors read both stores for that period.

Steps: create the logging project as `docs/runbooks/production-hardening.md` section 3 describes (directly under the organization, owned by a security group, organization-apply and organization-plan roles granted), set the three keys, run the `state rm` commands above in a speculative-plan-reviewed change, then apply `gcp-organization`.

#### Cloud Run probes and a warm instance in production (gcp-workload, breaking)

Production Cloud Run services without `min_instances` now keep one instance warm. Cloud Run bills an idle instance, so this adds a monthly cost per service. Production means the environment's `is_production` is `true`. Set `min_instances: 0` on a service to keep scale-to-zero in production.

Every Cloud Run service now gets an HTTP startup probe (up to 120 seconds to become ready) and an HTTP liveness probe (every 30 seconds) on `health_check_path`. The default is `/`, which the bootstrap image serves. Set `health_check_path` to your health route. Set it to an empty string to keep Cloud Run's default TCP probe. The key is valid in `app_services`, in `gcp.environments.<env>.services` and in `config/landing-zone.yaml`.

The first apply rolls a new revision of each existing service. The delivery pipeline owns the image and Terraform ignores it, so the new revision runs the image that is deployed now. If your image does not answer `GET /` (or your path) with a 2xx status, the new revision fails its startup probe and Cloud Run keeps the old one serving. Check the path before you apply.

#### Unknown keys in the hub hybrid and region inputs fail the plan (gcp-network-hub, breaking)

The `vpn`, `interconnects` and `hub_additional_regions` inputs of `envs/gcp/network-hub` now reject keys the network-hub stage does not accept. The check covers the variable and the config file (`gcp.network.vpn`, `gcp.network.interconnect`, `gcp.network.additional_regions`), and the nested `advertised_ip_ranges`, `subnet_cidrs` and `secondary_ranges` entries. Before, a misspelled key was dropped silently, so its setting never reached the hub. Now the plan fails and the error names each unknown key. Fix the spelling, or remove the key. The accepted keys are in `envs/gcp/network-hub/allowed_keys.tf`.

#### Internal DNS domain from config (gcp-network-hub)

Nothing changes for an existing estate: the default stays `internal.local`, so the first plan shows no change. Before, `envs/gcp/network-hub` never passed `internal_domain` to the stage and no config key existed, so every estate's private root zone (`internal-root`) was named `internal.local.`. Now `gcp.network.internal_domain` in `config/landing-zone.yaml` (or the `internal_domain` variable) names it, for example `corp.example.com`. The value must be a lowercase DNS name of at least two labels, without a trailing dot. Every `gcp-workload-<env>` `internal-peering` zone follows it through `hub_network.dns_domain`.

Set it before the first apply of `gcp-network-hub`. **Do not change it on an existing estate without a plan for the records.** The `dns_name` of a `google_dns_managed_zone` cannot change in place ([provider schema, `ForceNew`](https://github.com/hashicorp/terraform-provider-google/blob/v8.0.0/google/services/dns/resource_dns_managed_zone.go)), so a new value replaces the zone and drops every record in it. `google_dns_managed_zone` is protected by `destroy_guard`, so the run stops until the security team overrides it. To change the domain:

1. List the records in the `internal-root` zone (`gcloud dns record-sets list --zone internal-root --project <dns project>`) and save them.
2. Change `gcp.network.internal_domain`, apply `gcp-network-hub` with the `destroy_guard` override, then apply every `gcp-workload-<env>` so each peering zone takes the new domain.
3. Create the records again under the new domain and move clients to the new names.

#### Hub routes announced on-premises and hybrid DNS (gcp-network-hub, breaking)

**Breaking: this changes what on-premises learns over BGP.** It applies to an estate with the hub HA VPN (`gcp.network.vpn.enabled: true`) or a Cloud Interconnect attachment (`gcp.network.interconnect`) whose `advertised_ip_ranges` is empty.

Before, the Cloud Router used DEFAULT mode. It announced the hub VPC's own subnets and never the peered environment VPCs, so on-premises could not reach an environment. Now the router uses CUSTOM mode and announces:

- every hub subnet (the `ALL_SUBNETS` group, which is what DEFAULT mode announced);
- every `gcp.environments.<env>.cidr_block`;
- `35.199.192.0/19`, when `gcp.network.hybrid_dns.forward_zones` lists a zone (Cloud DNS sends forwarded queries from it).

On-premises keeps every route it learned before and learns the environment CIDRs (and the Cloud DNS range) in addition. Check that the on-premises routers accept the new prefixes, and that nothing on-premises already uses an environment CIDR. To keep the old announcement, set `advertised_ip_ranges` on the VPN or the Interconnect: an explicit list wins, and the router then announces exactly that list (add `advertised_groups: [ALL_SUBNETS]` on the VPN to keep the hub subnets).

The same estates also get an inbound DNS server policy on the hub VPC (`<prefix>-hub-inbound`). Cloud DNS takes one address from every hub subnet for it; on-premises resolvers can forward the internal domain to those addresses (`gcloud compute addresses list --filter='purpose="DNS_RESOLVER"'`). A VPC network takes one DNS server policy: if you attached one to the hub VPC outside this repository, import it or set `gcp.network.hybrid_dns.enable_inbound_forwarding: false` before you apply. Estates without the VPN or an Interconnect see no change. Steps: [docs/runbooks/gcp-hybrid-connectivity.md](docs/runbooks/gcp-hybrid-connectivity.md#routes-announced-on-premises).

#### Production VPC-SC dry-run fails the plan (gcp-workload, breaking)

**Breaking: a production `gcp-workload-<env>` plan that passed before now fails.** The `vpc_sc_enforced_in_prod` check only warned. It is replaced by `terraform_data.production_vpc_sc_enforced`, whose precondition fails the plan when the environment is production (`environment_config.<env>.is_production = true`) and its VPC-SC perimeter is absent or in dry-run. Dry-run gives no exfiltration protection.

Before you plan a production workload, do one of these:

1. **Enforce the perimeter (recommended).** Read the dry-run violation logs (`protoPayload.metadata.dryRun = true`) and add an ingress or egress rule for each legitimate caller. The environment's own plan and apply SAs are already admitted once gcp-projects publishes `environment_config.<env>.automation_identities`. Then set `vpc_sc_enable_dry_run = false` (or name the `prod-gcp-workload` preset) and apply.
2. **Set a time-boxed waiver during a first rollout.** Add it for that workspace in `config/tfc-workspaces.yaml` (its CODEOWNERS line lists the platform and the security team, so either team's approval satisfies it) and re-apply tfc-admin:

   ```yaml
   workspaces:
     gcp-workload-prod:
       production_vpc_sc_dry_run_waiver:
         reason: First rollout, reading the dry-run violation logs
         expires: "2026-12-31"
   ```

   `reason` must not be empty and `expires` must be a real `YYYY-MM-DD` date. The waiver stops working after that date (UTC), and the plan fails again. Remove it when the perimeter is enforced.

The guard is a `terraform_data` resource with no cloud side effect. The first plan of a production workload creates it.

#### Audit-log retention from config (gcp-organization)

`audit_log_retention_days` is now an input of the `gcp-organization` root. Null reads `compliance.audit_log_retention_days` in `config/landing-zone.yaml`, else 365 days, the value the root used before. With neither set, the plan does not change.

The value sets the age of the lifecycle Delete rule on the audit bucket and on its access-log bucket. With `gcp.enable_audit_bucket_lock: true` it is also the locked retention period. The plan fails when:

- the value is below the floor of a listed `compliance.frameworks` entry (pci_dss 365, hipaa 2190, fedramp_moderate 913 days); or
- the lock is on and the value is below 365. A bucket that this root locked earlier is locked at 365 days, and GCS refuses any decrease of a locked retention period.

A floor is a minimum. It does not prove that a framework is met.

Before you raise the value:

- More days mean more stored audit logs and a higher storage cost.
- On a locked bucket, a raised period cannot be lowered again. Every object then stays undeletable for the new period, even by an administrator. Set the period from your retention schedule before you apply.
- On an unlocked bucket, a lower value later makes the lifecycle rule delete older logs sooner.

#### Spokes resolve the internal zone through the hub VPC (gcp-bootstrap, gcp-organization, gcp-projects, gcp-network-hub)

**Breaking: apply the GCP layers in order.** Each `gcp-workload-<env>` peering zone `internal-peering` targets the hub VPC. The `internal-root` zone was bound only to the DNS anchor VPC (`dns-vpc-core`), so the hub VPC had no zone for the internal domain and every lookup from a spoke returned NXDOMAIN. Creating that peering zone also needs `roles/dns.peer` on the hub project, which the workload apply SAs did not hold.

What changes:

- gcp-bootstrap adds `roles/dns.peer` to the `delegated_network_folder_roles` output.
- gcp-organization adds it to the condition of the projects-apply delegated folder IAM grant on the shared folder.
- gcp-projects grants `roles/dns.peer` to each workload apply SA on the shared folder (`google_folder_iam_member.workload_dns_peer`, output key `workload-dns-peer|<env>`). The role holds only `dns.networks.targetWithPeeringZone`.
- gcp-network-hub binds `internal-root` to the hub VPC as well. The provider updates `private_visibility_config` in place, so the zone and its records stay.

Apply order for this release: `gcp-bootstrap`, `gcp-organization`, `gcp-projects`, then `gcp-network-hub`, then each `gcp-workload-<env>`. If gcp-projects runs before gcp-organization, its new grant fails with a permission error; apply gcp-organization and run gcp-projects again.

If you supply the bootstrap contract in `config/landing-zone.yaml` (`gcp.contracts.bootstrap`), add `roles/dns.peer` to its `delegated_network_folder_roles` list. If you supply a `network_hub` contract for a hub that gcp-network-hub does not manage, bind the internal zone to that hub VPC and grant `roles/dns.peer` on its project yourself.

#### The delegated folder IAM grant is split into conditions of 10 roles (gcp-bootstrap, gcp-organization, gcp-projects)

IAM accepts at most 10 roles in one `modifiedGrantsByRole` `hasOnly()` list. The projects-apply delegated `folderIamAdmin` had one condition per folder with the whole allow-list (36 roles on each environment folder and 13 on the shared folder by default), so IAM rejected it. Each folder now gets one binding per 10 roles of its sorted list. Chunk 0 keeps the old address (`google_folder_iam_member.projects_delegated_folder_iam["<folder>"]`), condition title and description. Later chunks are `["<folder>|<i>"]` with the title `delegated_folder_role_grants_<i>`.

What the plans show:

- gcp-organization: a folder with 10 roles or fewer plans no change. A folder with more than 10 roles plans new bindings for each chunk. If its old single binding is in state, chunk 0 is replaced, because the provider replaces an IAM member when its condition changes.
- gcp-bootstrap, only with `enable_org_level_folder_iam_delegation = true`: the legacy org-level binding is split the same way (`[0]`, `[1]`, and so on). With the default (off), there is no change.
- gcp-projects: no resource change. The google provider now runs with batching off, so each folder IAM change is its own request and the apply takes longer.

No action is needed beyond the usual apply order: `gcp-bootstrap`, then `gcp-organization`, then `gcp-projects`.

#### No US defaults in the network stages (net-hub, net-spoke, dns-anchor)

`modules/gcp/stages/net-hub`, `net-spoke` and `dns-anchor` now require `region`. Before, it defaulted to `us-central1`. In `net-spoke`, `flow_logs_export.bigquery_location` and `storage_location` now default to the spoke's region, not `US`. The roots and the `environment` and `network-hub` stages already pass these values, so only direct callers of the three stages change. An existing flow-log dataset created in `US` would be replaced if its location changes: set `bigquery_location = "US"` to keep it.

#### The environment perimeter has no default VPC-SC rules (gcp-workload)

`modules/gcp/stages/environment` no longer adds a default ingress or egress rule:

- The old egress rule let any identity copy storage data to any project.
- The old ingress rule named a Workload Identity pool as a source. VPC-SC does not accept that, so it never matched.

Set `vpc_sc_ingress_policies` and `vpc_sc_egress_policies` with named identities and `projects/<number>` targets, as in `modules/gcp/stages/environment/examples/vpc-sc`. Before you enforce a perimeter, add an ingress rule for the workload's TFC identities. The plan now rejects a pool as an ingress source, and rejects `ANY_IDENTITY` egress to `*`. The stage input `admin_project_number` is deprecated and ignored.

#### Workload identity providers may not upload a JWKS (gcp-organization)

`custom.wifProviderTenantPinned` now also denies any provider for a pinned issuer (TFC or GitHub Actions) that sets `oidc.jwks_json`. With an uploaded JWKS, the key holder could sign any token while still passing the issuer and condition pins. Remove any uploaded JWKS from such providers before you apply gcp-organization.

#### The organization plan identity loses roles/logging.viewer (gcp-bootstrap, re-audit-2 SEC-2)

**Who:** every estate that applies gcp-bootstrap.
**What changes:** `<prefix>-organization-plan` no longer holds `roles/logging.viewer` at the org node. That role holds `logging.logEntries.list`, so a speculative gcp-organization plan could read the log entries of every project. The plan SA gets the new org custom role `landingZoneLoggingConfigViewer` in its place. The role holds only these Cloud Logging configuration reads: `get` and `list` on sinks, buckets, links, log-based metrics, views and exclusions, `logging.settings.get`, and `logging.buckets.listEffectiveTags` / `listTagBindings`. The gcp-bootstrap plan creates the custom role and one org binding, and removes the `roles/logging.viewer` binding. No required input changes (new optional input `logging_config_viewer_role_id`). No other stage changes.

Apply gcp-bootstrap, then run a gcp-organization plan. It must show no permission error on the org sinks, the org logging settings, the log buckets, the linked dataset or the log-based metrics. If a deleted custom role with the same ID exists from the last 37 days, set `logging_config_viewer_role_id` to a new ID.

#### IAM-controlling workload roles are no longer delegable (gcp-bootstrap, gcp-organization, gcp-projects)

projects-apply could grant itself any delegated role on an environment folder, because a folder IAM condition limits roles but not members. It can no longer grant these roles:

- `projectIamAdmin`
- `serviceAccountAdmin`
- `serviceAccountKeyAdmin`
- `serviceAccountTokenCreator`
- `workloadIdentityPoolAdmin`

gcp-organization now grants them to each workload SA directly.

**Upgrade order:**

1. Apply gcp-bootstrap.
2. Apply gcp-organization. It creates the direct grants. The bindings already exist, so nothing changes in IAM.
3. Before you apply gcp-projects, remove its copies of those grants from its state, or its apply tries to delete bindings that gcp-organization now owns. List them with:

   ```bash
   terraform state list | grep 'workload_sa_folder_roles\[' | grep -E 'projectIamAdmin|serviceAccountAdmin|serviceAccountKeyAdmin|serviceAccountTokenCreator|workloadIdentityPoolAdmin'
   ```

   Run `terraform state rm '<address>'` for each. The plan must then show no change to `workload_sa_folder_roles`.
4. Apply gcp-projects.

#### Data-plane admin workload roles are no longer delegable (gcp-bootstrap, gcp-organization, gcp-projects, breaking)

projects-apply could grant itself any delegated role on an environment folder, for example `secretmanager.admin` on a production folder, and then read every secret. These roles join the non-delegable list. gcp-organization now grants them to each workload SA directly:

- `iam.serviceAccountUser`
- `secretmanager.admin`
- `cloudkms.admin`
- `storage.admin`
- `run.admin`
- `bigquery.admin`
- `pubsub.admin`
- `artifactregistry.admin`
- `resourcemanager.projectCreator`

The workload SAs keep every role. Only the stage that grants them changes. A custom `non_delegable_workload_folder_roles` input on gcp-organization or gcp-projects replaces the default list: add the new roles to it, and keep the two inputs equal.

**Upgrade order.** Do not run a workload apply between the steps:

1. Apply gcp-bootstrap. The `delegated_workload_folder_roles` output loses the nine roles.
2. Apply gcp-organization. It creates the direct grants. The bindings already exist, so nothing changes in IAM. The delegated `folderIamAdmin` conditions on the environment folders lose the nine roles.
3. Before you apply gcp-projects, remove its copies of those grants from its state. Otherwise its apply tries to delete bindings that gcp-organization now owns (and projects-apply's condition no longer admits them). List them with:

   ```bash
   terraform state list | grep 'workload_sa_folder_roles\[' | grep -E 'iam\.serviceAccountUser|secretmanager\.admin|cloudkms\.admin|storage\.admin|run\.admin|bigquery\.admin|pubsub\.admin|artifactregistry\.admin|resourcemanager\.projectCreator'
   ```

   Run `terraform state rm '<address>'` for each. The plan must then show no change to `workload_sa_folder_roles`.
4. Apply gcp-projects.

#### organization-apply cannot reach a guardrail-owner role (gcp-bootstrap, gcp-organization, breaking)

organization-apply held an unconditional org `iam.securityAdmin`, so it could grant itself `roles/iam.denyAdmin` and delete the containment deny policy. It also held org `folderAdmin`, whose `resourcemanager.projects.setIamPolicy` reaches every project, including the admin project and the `<prefix>-guardrails-apply` SA in it. Now:

- organization-apply holds `folderCreator`, `folderEditor` and `folderIamAdmin` at the org node instead of `folderAdmin`. These cover what gcp-organization does on folders (create, rename, delete, folder IAM). Folder tag bindings use its `tagUser`, and folder org policies its `orgpolicy.policyAdmin`.
- Its org `iam.securityAdmin` carries `modifiedGrantsByRole.hasOnly(<organization_apply_grantable_roles>)`. The default list (gcp-bootstrap) is `billing.admin`, `logging.bucketWriter`, `logging.logWriter`, `storage.objectCreator` and `cloudkms.cryptoKeyEncrypterDecrypter`. The plan rejects any role that controls IAM, identities, projects or PAM, and more than 10 roles.
- gcp-bootstrap grants the standing `organizationAdmin` of the org admin groups (`gcp.organization_admin_groups`, or its new variable `organization_admin_members`). gcp-organization grants it to nobody, and fails its plan when an org admin it expects is missing from the gcp-bootstrap contract, or when this stage would grant a role the condition does not admit.
- The gcp-bootstrap contract has two new keys, `organization_apply_grantable_roles` and `organization_admin_members`. A hand-supplied `bootstrap_contract` (or `gcp.contracts.bootstrap`) should copy both. Without them the plan warns and cannot check.

**Upgrade order.** Apply this change before the gcp-projects steps of the data-plane roles entry above: gcp-bootstrap, then gcp-organization (both entries), then gcp-projects.

1. **Apply `gcp-bootstrap`.** It takes over the standing
   `roles/resourcemanager.organizationAdmin` of the org admin groups
   (`module.bootstrap.google_organization_iam_member.org_admins`). The members
   already hold the role, so nothing changes in IAM. It also replaces
   organization-apply's org `folderAdmin` with `folderCreator`, `folderEditor`
   and `folderIamAdmin`, and adds the `modifiedGrantsByRole` condition to its
   `iam.securityAdmin`. If gcp-organization runs with
   `gcp_overrides.allow_user_principals_for_break_glass = true`, first set the
   gcp-bootstrap variable `organization_admin_members` to the groups plus
   `user:<admin_email>` and `user:<break_glass_user>`.
2. **Remove the org-admin grants from the `gcp-organization` state** without
   deleting them:

   ```bash
   make state-rm-gcp-organization ADDR='module.organization.module.organization.google_organization_iam_member.org_admins'
   ```

3. **Plan `gcp-organization`.** The plan must show no destroy of
   `org_admins`. It fails with a named role or member when the gcp-bootstrap
   contract does not cover what this root grants: fix the gcp-bootstrap input
   (`organization_apply_grantable_roles` or `organization_admin_members`),
   re-apply gcp-bootstrap, and plan again.
4. **Apply `gcp-organization`.**

Run no other `gcp-organization` apply between steps 1 and 4. The guards: a
`gcp-organization` plan against a gcp-bootstrap state from before step 1 fails
(`terraform_data.bootstrap_grants_org_admins`). If you skip step 2, the plan
shows the `org_admins` bindings as destroyed: stop and run step 2. (The
conditional `securityAdmin` should refuse that removal with 403, but this is
not validated on a real organization.) Break-glass and the org admin groups
keep `organizationAdmin` throughout.

#### Production Cloud SQL is regional by default (gcp-workload)

In an environment with `is_production`, app-service databases are created with REGIONAL availability, unless the entry sets `database.enable_high_availability: false`. An existing zonal production database changes to regional in place, with a short restart. The new option `database.backup_location` keeps backups in another region.

#### Production app services need a service team (gcp-workload)

In a production environment, every `app_services` entry must set `service_team`, so app principals do not share the Shared VPC host project. To keep a service in the host project, set `enable_host_project_workloads = true` on the workload.

#### The app deploy identity pins the GitHub environment (gcp-workload, breaking)

**Breaking.** A service with `github` but neither `ref` nor `environment` used to trust every branch, tag and environment of its repository. Its deploy SA now trusts only the GitHub environment named after the landing-zone environment key (`gcp.environments.<env>`, the stage's `var.environment`). The binding moves from `attribute.repository_id/<id>` to `attribute.repo_env/<id>/<env>`. This matches AWS app-services.

GitHub adds the `environment` claim to the OIDC token only for a job that declares `environment:`. A deploy job without it maps to `<id>/-` and matches no binding, so `google-github-actions/auth` fails. Before you apply `gcp-workload-<env>`, do one of these for each such service:

1. Add `environment: <env>` to the deploy job (for example `environment: dev` in `gcp-workload-dev`), and create that GitHub environment in the app repository. Move the deploy variables to it if you like.
2. Or set `github.ref` (for example `refs/heads/main`) on the service entry. The binding is then `attribute.repo_ref/<id>/<ref>`, and the job needs no environment.
3. Or set `github.environment` to the GitHub environment the job already uses.

The apply replaces the `roles/iam.workloadIdentityUser` binding (`member` is immutable). Do not run a deploy during the apply.

#### Admin containment follows the break-glass group (gcp-organization, gcp-guardrails)

Admin containment is now on when `gcp.break_glass_group` is set, even with no production environment. To keep it off, set `gcp.admin_containment: false`.

#### The hub VPC-SC perimeter now covers only the hub and DNS projects (gcp-network-hub)

The hub perimeter no longer lists the environment host projects. Each environment host project is protected by its own environment perimeter, so production and non-production never share one. In org-wide-policy mode the old layout was also invalid: a project can belong to only one regular perimeter of a policy. `stages/network-hub` takes two new inputs, `hub_project_number` and `dns_project_number`, and requires them when `vpc_sc_access_policy_name` is set. The `gcp-network-hub` root reads them from the gcp-projects contract (`shared-hub`, `shared-dns`). On the next apply, the environment projects leave the hub perimeter. Before you enforce, confirm that every environment has its own perimeter.

#### Cloud NAT no longer covers the database subnets (gcp-network-hub, gcp-workload)

By default, Cloud NAT in `stages/net-hub` and `stages/net-spoke` now translates only the private tier. A VM in a database subnet has no internet path, even without the `database` network tag. If a database-tier workload needs outbound internet, set `nat.include_database_subnets = true`.

#### Network data-plane alerts are on by default (gcp-network-hub, gcp-workload)

`stages/net-hub` and `stages/net-spoke` now create Cloud Monitoring alert policies for the features that exist: VPN tunnel down, BGP session down, Cloud NAT allocation failures and Cloud NAT packet drops. To get notifications, set `alerting.notification_channel_ids` (`network_alerting` on the gcp-network-hub root). Set `alerting.enabled = false` to turn them off.

#### Opt-in Secure Web Proxy for central egress (preview)

The new module `modules/gcp/network/secure-web-proxy`, the hub input `secure_web_proxy` and the spoke input `egress_proxy` add FQDN-allowlisted egress through one proxy in the hub, reached over Private Service Connect. They are off by default and not yet validated by a real apply. Rules match on host name: traffic is source-NATed and there is no TLS inspection.

#### The hub owns the hub side of each environment peering (gcp-network-hub, gcp-workload, gcp-projects)

Every `gcp-workload-<env>` used to create the reverse peering
`hub-peering-reverse` on the hub VPC, so a second environment collided on that
name, and the workload apply SA had no right on the hub project anyway. Now
`gcp-network-hub` creates `hub-to-<env>` for each peering-mode environment
whose spoke network exists, and the workload creates only its own side.
`gcp-projects` grants the network-hub SAs read-only `roles/compute.viewer` on
each environment folder so the hub can list the spoke networks.

**Upgrade order (an applied peering-mode environment loses hub connectivity
between steps 3 and 4):**

1. Apply `gcp-projects` (the new viewer grants).
2. Do not apply `gcp-network-hub` yet. It plans `hub-to-<env>` for every
   existing spoke, and GCP rejects that peering while the old
   `hub-peering-reverse` still pairs the same two networks.
3. Apply each `gcp-workload-<env>`: it destroys its `hub-peering-reverse`.
4. Apply `gcp-network-hub`: it creates `hub-to-<env>`. Each workload's
   `hub_peering_state` output reads `ACTIVE` after its next refresh.

For a **new** environment, queue `gcp-network-hub` once more after the
environment's first workload apply: the hub side can only be created once the
spoke network exists.

#### Internet egress route for Cloud NAT (gcp-network-hub, gcp-workload-<env>)

**Behaviour change.** `tiered-vpc` creates every VPC with
`delete_default_routes_on_create = true`, and nothing added a route back, so
Public Cloud NAT (which only uses routes whose next hop is the default internet
gateway) had no path to the internet. `net-hub` and `net-spoke` now set the new
`tiered-vpc` input `enable_internet_egress_route = var.nat.enabled`, which
creates `<network>-egress-internet` (`0.0.0.0/0`, next hop
`default-internet-gateway`, priority 1000). The tier firewall still governs
egress; the database tier still denies it.

Manual steps:

1. Review the plan on `gcp-network-hub` and each `gcp-workload-<env>`: one new
   `google_compute_route` per network with NAT on.
2. If you added your own default route out of band, import it to
   `module.<network>.google_compute_route.internet_egress[0]` or remove it
   first, so the two do not overlap.
3. If a network must stay without internet egress, set `nat.enabled = false`.

#### IAP TCP forwarding through the hub firewall policy (gcp-network-hub)

The hub hierarchical policy denied tcp 22/3389 from `0.0.0.0/0` at priority 500.
Hierarchical rules run before VPC rules and a match stops evaluation, so it also
blocked IAP (`35.235.240.0/20`). A priority-400 `goto_next` rule for the IAP
range now hands those flows to the VPC firewall, where the `tiered-vpc` IAP rule
decides them. No manual step; review the plan on `gcp-network-hub`.

#### google / google-beta provider 8.x (every GCP workspace)

**Breaking for every fork.** Every GCP `versions.tf` (modules, roots,
examples, `templates/shared/module`, `tests/e2e/gcp`) now pins
`google`/`google-beta` `~> 8.0`, and every lockfile resolves both to 8.10.0.
A fork that pins google 7.x anywhere fails `terraform init`.

Manual steps:

1. **Forks bump too.** Change any fork-owned `hashicorp/google` or
   `hashicorp/google-beta` constraint to `~> 8.0`, then re-lock each root you
   own with `terraform providers lock -platform=linux_amd64
   -platform=darwin_arm64 -platform=darwin_amd64`. `make consistency` fails on
   a GCP `versions.tf` that is not `~> 8.0`, or on two google versions locked
   in different lockfiles.
2. **No way back.** The 8.x provider upgrades resource state in place (below).
   A 7.x provider can fail to read state an 8.x apply has written, so do not roll a
   workspace back to 7.x after its first 8.x apply.
3. **Sandbox (operator).** Plan every GCP workspace (`gcp-bootstrap`,
   `gcp-organization`, `gcp-guardrails`, `gcp-projects`, `gcp-network-hub`,
   each `gcp-workload-<env>`) in the sandbox. Each must show **0 changes**, or
   only the app-ingress item below. Anything else is an undocumented 8.x
   change: stop and record it in the sandbox upgrade log before promoting.

What changes on the first 8.x plan:

- **Secret Manager write-only version (state migration, no plan change).**
  `google_secret_manager_secret_version.secret_data_wo_version` is now a
  String, and the provider migrates each stored `N` to `"N"` when it reads
  the state. `modules/gcp/data/secret-manager` (and through it the SaaS secret
  bridge in `gcp-workload-<env>`) now passes `tostring()` of its counter, so
  the plan shows no diff and no secret version is replaced. The input
  `secret_value_versions` stays `map(number)`. 8.x treats a `"0"` version as
  unset and forces replacement; the module's validation already rejects
  values below 1.
- **app-ingress backend scheme (explicit now).** 8.x changes the
  `google_compute_backend_service` `load_balancing_scheme` default from
  `EXTERNAL` to `EXTERNAL_MANAGED`. `modules/gcp/network/app-ingress` (used by
  `modules/gcp/stages/environment`, i.e. `gcp-workload-<env>`) left it unset
  while its forwarding rules were `EXTERNAL_MANAGED`; it now sets
  `EXTERNAL_MANAGED`. An `EXTERNAL` backend behind `EXTERNAL_MANAGED`
  forwarding rules is a mix GCP rejects, so a working load balancer cannot hold
  it: a fresh plan, or a state already at `EXTERNAL_MANAGED`, shows no change.
  If a plan nevertheless shows a `load_balancing_scheme` update (a state written
  some other way), do not apply it directly to a serving load balancer: GCP
  moves a backend between the two schemes only through the
  `external_managed_migration_state` flow (`PREPARE` → `TEST_BY_PERCENTAGE` →
  `TEST_ALL_TRAFFIC`, then the scheme change). Run that flow in the sandbox
  first and record it in the sandbox upgrade log.
- **Deprecated attributes leave two whole-resource outputs (no resource
  change).** `modules/gcp/network/subnet` output `subnet` no longer carries
  `fingerprint`, and `modules/gcp/network/vpc` output `network` no longer
  carries `numeric_id` (read `network.network_id`). Both are deprecated in the
  provider and warned on every plan. No in-repo caller reads them; a fork root
  that does must switch before upgrading.
- **Not affected.** The other 8.0 breaking changes either name resource types
  this repo does not use, or touch arguments it never sets (`cdn` and every
  forwarding rule set their scheme explicitly; `gke-autopilot` sets no
  `enable_components`; no BigQuery dataset sets `default_collation`). The full
  table is in [provider-upgrades](docs/guides/provider-upgrades.md).

#### GCP deny policies move to the security-team `gcp-guardrails` workspace

In the default `guardrail_owner_mode = "separate"` the org IAM deny policies
(admin containment `contain-admin-identity` plus `iam_deny_policies`) are now
authored and applied by a new root, `envs/gcp/guardrails` (workspace
`gcp-guardrails`, stage `modules/gcp/stages/guardrails`). This replaces the
manual `gcloud iam policies create|update` step. The workspace sits in its own
HCP project where only the security team has access, and it runs as the
gcp-bootstrap guardrails SAs, WIF-bound by workspace ID only.

**What changes on the next plan (no manual step):**

- **gcp-organization (separate mode)** no longer builds the deny policies. Its
  `admin_containment_rules` and `guardrail_deny_policy_specs` outputs are empty,
  and a check warns if `iam_deny_policies` is still set there.
  `guardrail_deny_policy_specs` is deprecated and is removed in v1.0. The
  containment tag and its bindings are unchanged.
- **gcp-organization (legacy organization mode)** keeps applying the policies
  under the same state addresses. One fix is applied: the audit-store rule's
  condition now passes the namespaced IDs
  (`resource.matchTagId('tagKeys/<n>', 'tagValues/<n>')`) where it used to pass
  the bare numeric names. `contain-admin-identity` updates in place.
- **gcp-bootstrap** adds a `<prefix>-guardrails-plan` SA (`iam.denyReviewer`,
  `resourcemanager.tagViewer`, `organizationViewer`), gives the guardrails apply
  SA `resourcemanager.tagViewer`, and binds both to `gcp-guardrails` (variable
  `guardrails_workspace`) by its `tfc_workspace_ids` entry. There is never a
  binding by name. **A production estate fails the gcp-bootstrap plan** until
  `tfc_workspace_ids` holds the `gcp-guardrails` ID. tfc-admin writes it when
  `set_gcp_bootstrap_workspace_ids` is on (the default); for the local phase-0
  apply use its `gcp_bootstrap_tfvars` output. `guardrails_workspace = null`
  opts out and keeps only the PAM break-glass path.
- **tfc-admin** adds the `gcp-guardrails` workspace and the
  `<project_name_prefix>guardrails` project (config key
  `org.tfc.guardrails_project` overrides the name). It also adds the
  `security_team_id` variable (default null; the security team gets write on
  that project, and no other team gets any access). With it null, a check warns
  and only organization owners can run the workspace.
  `speculative_enabled = false`, `auto_apply = false`, no UI destroy plans.

**Manual steps for an existing separate-mode deployment** (the policies were
applied by hand from `guardrail_deny_policy_specs`):

1. Create a `security` team in HCP Terraform (owners) and set
   `security_team_id`. Apply `tfc-admin`.
2. Apply `gcp-bootstrap` (it picks up the `gcp-guardrails` ID).
3. Move any `iam_deny_policies` from the gcp-organization variables to a
   committed `envs/gcp/guardrails/guardrails.auto.tfvars` (CODEOWNERS: the
   security team alone, so a security approval is required; `.gitignore` exempts it). Do not set them as `gcp-guardrails`
   workspace variables: the security team's grant is variables read-only, and
   the workspace gets no shared variable set.
   - If gcp-organization runs with `enable_principal_access_boundary = true`,
     set `gcp.principal_access_boundary: true` in `config/landing-zone.yaml`
     instead (gcp-bootstrap, gcp-organization and gcp-guardrails all read it;
     variable > config > false). Otherwise gcp-guardrails plans the containment
     policy WITHOUT the boundary update/delete/unbind rules and drops them on
     its first apply. Then remove the per-root variable.
   - If gcp-bootstrap sets `tfc_project_ids` (the WIF provider's TFC project
     allow-list), add the new guardrails HCP project's `prj-...` ID (tfc-admin
     output `project_ids["guardrails"]`) and re-apply gcp-bootstrap, or the
     gcp-guardrails token is rejected by the provider condition.
4. In `gcp-guardrails`, adopt each existing policy instead of creating it. The
   create would fail with 409. Run the import as the security team with an
   `import` block in a reviewed PR, or once from the workspace:
   `terraform import 'module.guardrails.module.iam_deny.google_iam_deny_policy.this["contain-admin-identity"]' 'cloudresourcemanager.googleapis.com%2Forganizations%2F<ORG_ID>/contain-admin-identity'`.
5. Queue a run on `gcp-guardrails`; the security team confirms it. Expect an
   in-place update of the tag condition (namespaced IDs, see above).

**Tag IDs are namespaced (all estates).** `google_tags_tag_key` /
`google_tags_tag_value` `.name` is the bare numeric ID, but tag-value
parents, tag bindings and `matchTagId` take `tagKeys/<n>` / `tagValues/<n>`.
`modules/gcp/governance/tags` now outputs the namespaced form (and builds the
tag-value parent from it). Consumers that took the bare form were wrong:
gcp-projects' `tag_bindings` validation (`^tagValues/[0-9]+$`) rejected it,
and the containment bindings and deny condition passed bare numbers. Expect on
the next gcp-organization plan:
- `google_tags_tag_value.values`: no change. `parent` is ignored after create
  because it is immutable and fixed by the key.
- `google_tags_tag_binding.environment` and
  `google_tags_location_tag_binding.containment_*`: if your state holds a bare
  `tag_value`, they are **replaced** (`tag_value` is immutable). Each binding is
  briefly absent; with containment on, apply outside change windows that touch
  the audit store.
- `contain-admin-identity` (organization mode): the condition updates in place.
- The `tag_keys` / `tag_values` outputs of gcp-organization change form. A
  `gcp.contracts.organization.tag_values` override in config must use
  `tagValues/<n>`, as the validation already required.

**Migrating from `guardrail_owner_mode = "organization"` to `"separate"`:**
switch gcp-bootstrap first. Then run
`terraform state rm 'module.organization.module.iam_deny.google_iam_deny_policy.this'`
in gcp-organization before its next apply (its apply SA can no longer delete
the policies, which is the point). Then follow steps 1-5. Do not run
`gcp-guardrails` while either root is still in organization mode: both would
manage the same policies.

**v1.0 legacy removal:** `guardrail_owner_mode = "organization"` (the in-stage
apply, and `roles/iam.denyAdmin` on the organization apply SA) and the
`guardrail_deny_policy_specs` output are removed in v1.0.

#### GitHub workload identity: exact-match owner pin, ref/env pins in bindings

Every GitHub Actions workload identity provider this repo creates now has the
attribute condition `assertion.repository_owner_id == "<id>"` and nothing else.
`custom.wifProviderTenantPinned` accepts only that exact string. Repository, ref
and environment pins moved into the principalSet each service account is bound
to.

**`modules/gcp/iam/workload-identity` (breaking inputs):**

- `github_attribute_condition_override` is removed. A custom condition could
  never satisfy the exact-match tenant pin. Pin repositories, refs and
  environments through `github_sa_bindings` and `github_allowed_refs` instead.
- `github_organization` is removed. The condition pins the immutable
  `github_repository_owner_id`, never the renameable owner name.
- `github_repository_owner_id` is required when `enable_github_provider = true`.
- `github_allowed_refs` entries must be exact refs (`^[A-Za-z0-9_./-]+$`): a
  principalSet value cannot hold a wildcard. When it is set, each
  `github_sa_bindings` entry needs `repository_id`, and is bound once per ref on
  `attribute.repo_ref/<repository_id>/<ref>`. With one ref the binding keeps its
  for_each key; with several, each key becomes `<key>:<ref>`.
- **Behaviour change:** with `github_allowed_refs` empty the old computed
  condition still limited `assertion.sub` to `refs/heads/main`. The bindings now
  stay on `attribute.repository_id`, so any ref of the bound repository can
  impersonate. Set `github_allowed_refs = ["refs/heads/main"]` to keep the old
  restriction.

**`modules/gcp/stages/app-services` / `gcp-workload-<env>`:**

- `github_repository_owner_id` is required once a service declares `github`
  (`gh api orgs/<org> --jq .id`). It was optional.
- `services[*].github.ref` must match `^[A-Za-z0-9_./-]+$` and
  `.environment` `^[A-Za-z0-9_.-]+$` (no `/`: the environment is the last
  `/`-joined part of `repo_ref_env`, so a `/` would let two ref/environment
  pairs collide). `environment` may not be `-` (the value a token without an
  environment claim maps to). Rename a GitHub environment whose name has a `/`.

**What the next apply does (no manual step):**

- The GitHub providers (app-services `github`, gcp-bootstrap `gh_oidc`) update
  in place: the condition is normalised to the canonical double-quoted form and
  three mapped attributes are added.
- Each GitHub `roles/iam.workloadIdentityUser` binding whose pin changes is
  replaced (`member` is immutable). For the few seconds between the delete and
  the create, that deploy SA cannot be impersonated; do not run a deploy during
  the apply.

**Before you apply `gcp-organization` with `wif_github_owner_ids` set:** apply the
workload and bootstrap roots first. A provider that still carries the old
condition is denied on its next UPDATE (not on its existing state) until it is
rewritten.

#### NCC hub/spoke connectivity, opt-in (gcp-bootstrap, gcp-projects, gcp-network-hub, gcp-workload-&lt;env&gt;)

**No action by default.** New config keys `gcp.network.ncc_hub` (`enabled`,
`preset_topology`), `gcp.network.connectivity` and
`gcp.environments.<env>.network_connectivity` all default to today's VPC
peering. Unset, the upgrade apply plans no change in any root.

**Contract:** the gcp-network-hub `contract.hub_network` gains `ncc_hub_id` and
`ncc_spoke_group`. Both are null while the hub is off. gcp-workload reads them
optionally, so an N-1 gcp-network-hub state without them still plans (in peering
mode).

**Adopting it** (after a sandbox proof): follow
[docs/runbooks/gcp-peering-to-ncc-migration.md](docs/runbooks/gcp-peering-to-ncc-migration.md).
Turning NCC on in the config changes four roots, applied in order:

1. gcp-bootstrap adds folder-scoped NCC roles: `hubAdmin` + `spokeAdmin` for the
   network-hub SAs on the shared folder, `spokeAdmin` for each workload SA on
   its own environment folder, and `hubViewer` for the plan SAs.
2. gcp-organization updates the delegated folderIamAdmin condition in place.
3. gcp-projects enables `networkconnectivity.googleapis.com` on `shared-hub` and
   every `<env>-host` project, and grants the roles.
4. gcp-network-hub creates the hub, its center spoke and the spoke group's
   auto-accept list.

Switching an environment to `ncc` then **deletes its hub peering** in the same
apply that creates its spoke. Run the runbook's pre-flight first.

#### gcp app-services: Cloud Run Jobs and SLOs (additive)

`services[*].runtime` (default `"cloud-run"`) and `services[*].slo` (default
null) are new. With the defaults every existing address plans unchanged. The
`services` output gains `runtime`, `job_name` and `slo_name`; `github_actions`
gains `CLOUD_RUN_JOB`. There are no manual steps.

#### gcp-network-hub: HA VPN and Interconnect from config (opt-in)

`gcp.network.vpn` and `gcp.network.interconnect` now reach the existing hub
VPN/Interconnect modules. Off by default: no plan change when unset. Supply the
VPN pre-shared key with the write-only `vpn_shared_secret_wo` (rotate by raising
`vpn_shared_secret_wo_version`); it never enters state. The sensitive
`stages/net-hub` `vpn_shared_secret` and `network/vpn` `shared_secret` inputs
are legacy and are removed at v1.0.

**A secret change replaces the VPN tunnels.** Moving from the legacy input to
`vpn_shared_secret_wo`, or raising its version, recreates the tunnels, which
means an outage. With NCC, the hybrid spoke can block the replacement. Do it in a
maintenance window, following
[gcp-hybrid-connectivity](docs/runbooks/gcp-hybrid-connectivity.md).

With `gcp.network.ncc_hub.enabled` and `gcp.network.vpn.enabled` both set, the
tunnels also join the NCC hub's center group (`default` on MESH) as a hybrid
spoke. This is a new resource.

#### gcp-workload: composition moved into `modules/gcp/stages/environment`

`envs/gcp/workload` now calls one module, `module "environment"`
(`modules/gcp/stages/environment`). Every resource keeps its identity through
`envs/gcp/workload/moved.tf`. `module.host`, `module.budget`,
`module.service_team`, `module.vm_backup_policy`, `google_project_service.osconfig`,
`module.os_patch_management`, `module.saas_secret_bridge`, `module.app_services`
and `module.app_ingress` each move to `module.environment.<same>`, and the older
`module.host.*` network-core moves chain into them. There is no manual step: the
first plan of each `gcp-workload-<env>` workspace shows only "has moved" entries
and 0 to destroy. Root variables and outputs are unchanged.

- If you script against state addresses (`terraform state`, `-target`, imports),
  prefix them with `module.environment.`. The runbooks are updated.
- An input you set explicitly to `null` in tfvars now takes the stage's default
  instead of passing through as `null`. Unset inputs behave as before.
- The moved blocks are kept until v1.0.

#### gcp-organization: SCC v2 behind `scc_api_version` (opt-in)

`gcp_overrides.scc_api_version` (default `v1`, no change on upgrade) takes `v1`,
`both` or `v2`. In `both` mode the v2 notification and mute configs are created
next to the v1 ones, so subscribers receive every finding twice in two formats
until you finish. `v2` **destroys the v1 configs**. v1 and v2 cannot see each
other's configs. The Pub/Sub topics are shared and never replaced. Follow
[scc-v2-migration](docs/runbooks/scc-v2-migration.md).

#### gcp-organization: `disable_default_sink` is configurable

`gcp_overrides.disable_default_sink` (default `false`; gcp-organization's
`gcp_overrides` object, not a `config/landing-zone.yaml` key) is no longer hard-coded. It only takes
effect when `enable_logging_organization_settings` is on. Don't disable the
`_Default` sink unless a catch-all sink exists: the central Log Analytics sink
routes only Cloud Audit Logs.

#### gcp-network-hub / gcp-workload: additional regions (opt-in)

`additional_regions` is new on `network/tiered-vpc`, `stages/net-hub` and
`stages/net-spoke`. The stages expose it as `hub_additional_regions`
(`stages/network-hub`) and `network.additional_regions` (`stages/environment`).
In config it is `gcp.network.additional_regions` for the hub and
`gcp.environments.<env>.additional_regions` for a spoke. The default is `{}`, so
nothing changes on upgrade. Existing subnets and `integrated_nat[0]` keep their
addresses.

Adding a region creates three regional subnets (`<vpc>-{public,private,db}-<region>`).
Unless the region sets `nat: false`, it also creates a Cloud Router
`<vpc>-router-<region>` with Cloud NAT `<vpc>-nat-<region>`. Nothing is replaced
or destroyed.

- The new CIDRs must not overlap the primary subnets or each other.
- In `firewall_mode` `both`/`policy`, the tier policy rules update in place to
  include the new CIDRs.
- Under NCC with a non-empty `ncc.include_export_ranges`, add the new CIDRs
  there too.
- Shared VPC subnet grants are explicit: add the new subnet names to
  `service_teams.*.shared_vpc_subnets` for teams that deploy there.

### SaaS and cross-cloud

#### SaaS data residency check (saas, breaking, CMP-11)

**Who:** forks that apply a `saas-<name>` workspace and set
`saas.allowed_regions` or `aws.allowed_regions` in `config/landing-zone.yaml`.
Without either key nothing changes.

**What changes:** the `envs/saas` plan now fails when the stack would process
data outside the allow list. The list holds AWS region names. It is
`saas.allowed_regions` (new key), else `aws.allowed_regions`. The check reads:

- the Supabase region (`supabase_region`), which is an AWS region name; and
- the AWS region behind the Vercel function region (`vercel_serverless_region`),
  from the table at <https://vercel.com/docs/regions> (for example `lhr1` is
  `eu-west-2`). A code with no mapping fails the plan (fail closed).

The Vercel CDN and edge cache are global; the check does not cover them. See
`docs/compliance/third-parties.md`.

The Vercel region lists in `modules/vercel/project` and the saas stage now
match Vercel's table: `arn1`, `hkg1`, `syd1` and `yul1` are accepted, and
`sea1` (not in the table) is rejected.

**Before you plan `saas-<name>`:**

1. If `aws.allowed_regions` is set and your SaaS stack runs in another region on
   purpose, set `saas.allowed_regions` to the regions the stack may use.
2. Otherwise move `supabase_region` or `vercel_serverless_region` into the list.
   For an existing Supabase project, read the plan first: never apply a plan
   that replaces a project that holds data. Migrate the data instead.
3. If you use `sea1`, pick a listed region.

#### npm settings must come from .npmrc in vault-secrets (saas, breaking)

The bootstrap and reconcile provisioners now run `npm ci` under `env -i`. npm gets back only these environment variables, each one only when it is set:

- `PATH`, `HOME` and `TMPDIR`
- `npm_config_cache` and `NPM_CONFIG_CACHE`
- `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `http_proxy`, `https_proxy` and `no_proxy`
- `NODE_EXTRA_CA_CERTS`

Every other variable no longer reaches npm. This includes the provisioner secrets (`POSTGRES_URL`, `VAULT_DESIRED_JSON`, `SUPABASE_SSL_CERT`), the workspace's `SUPABASE_ACCESS_TOKEN`, and any other `npm_config_*` or `NPM_CONFIG_*` setting, such as `npm_config_registry`, `npm_config_userconfig`, `npm_config_strict_ssl` or a registry `_authToken`. `node` still gets the full environment.

If your apply runner set npm through environment variables, move the settings to an `.npmrc` file before you upgrade:

1. Registry auth (for example `//npm.example.com/:_authToken=...`): put it in `$HOME/.npmrc` on the apply runner (the agent image or its start script). Never commit a token.
2. A registry URL without secrets: put it in `$HOME/.npmrc`, or commit it as `registry=https://npm.example.com/` in `modules/supabase/vault-secrets/scripts/.npmrc`. npm reads that file as the project config because the command uses `--prefix modules/supabase/vault-secrets/scripts`.
3. A corporate proxy or CA bundle needs no change: the proxy variables and `NODE_EXTRA_CA_CERTS` still pass.

The trigger hashes do not include the command, so the upgrade itself re-runs no provisioner. A missing setting shows up on the next bootstrap or reconcile run as an `npm ci` failure (for example `E401`, `E404` or a TLS error).

#### vault-secrets installs its dependencies in each script run (saas)

`terraform_data.npm_install` is gone. It ran only when `package-lock.json` changed, so a later bootstrap or reconcile on a fresh runner failed with "module not found". Bootstrap and reconcile now each run `npm ci --ignore-scripts` in the same command, before `node`. `removed` blocks drop the old resource from state without running anything. The runner still needs Node.js 18+ and npm.

#### saas / vercel: function regions through `resource_config`

`vercel_project` now sets `resource_config.function_default_regions` and no longer
writes the deprecated `serverless_function_region`. A new
`function_default_regions` list overrides the old single-region input, which
stays as the fallback. Expect one in-place update to each `vercel_project`.

#### SaaS secret bridge writes its secret write-only

Applies to workloads with `enable_saas_secret_bridge = true`.

- **AWS (`aws-workload-<env>`).** `aws_secretsmanager_secret_version.saas_bridge`
  moves from `secret_string` to the write-only `secret_string_wo`. The plan is
  **expected** to show an in-place update, not a replacement (aws 6.45 and later
  switch in place, and the repo floor is 6.46), and the secret version is
  expected to hold no plaintext in state afterwards; confirm both with
  `terraform state pull` in the sandbox before relying on them. The secret's
  content does not change.
- **GCP (`gcp-workload-<env>`).** The secret was already write-only. Its
  version counter now follows `saas.bridge_rotation`. It stays 1 until you bump
  it, so the upgrade re-writes nothing.
- **Rotation.** A write-only value is not diffed. After rotating a bridged
  Supabase secret, bump `saas.bridge_rotation`, apply `saas-<name>`, then apply
  each bridging workload
  ([saas-bootstrap](docs/runbooks/saas-bootstrap.md#bridging-secrets-to-a-workload-and-rotating-them)).
  Under Terraform 1.17 the workload plan fails until `saas-<name>` has applied
  the new number (see "SaaS secret bridge reads ephemerally").
- **The read itself.** This release still read the values through
  `data.terraform_remote_state.saas`, whose result is stored in the workload's
  state. The Terraform 1.17 release replaces it with `ephemeral "tfe_outputs"`,
  so the values no longer reach the workload's state (see "SaaS secret bridge
  reads ephemerally" under Terraform 1.17).

### All clouds

#### Deletion-protection inputs renamed to `enable_*deletion_protection`

**Who:** every fork that sets one of the old names in a module call, a tfvars file or a TFC workspace variable.
**What changes:** ten inputs now follow the `enable_` rule from `CLAUDE.md`. The old names stay as `deprecated` aliases. A set old name still works and warns. When both names are set, the new name wins. Old names are removed in v1.0. No plan changes and no state changes.

| Module or root | Old input | New input |
|---|---|---|
| `modules/gcp/network/tiered-vpc` | `deletion_protection` | `enable_deletion_protection` |
| `modules/gcp/stages/{dns-anchor,net-hub,net-spoke,environment}` | `deletion_protection` | `enable_deletion_protection` |
| `modules/gcp/governance/private-ca` | `deletion_protection` | `enable_deletion_protection` |
| `modules/aws/data/rds-aurora` | `deletion_protection` | `enable_deletion_protection` |
| `modules/aws/network/network-firewall` | `delete_protection` | `enable_deletion_protection` |
| `modules/aws/stages/app-services` | `alb_enable_deletion_protection` | `enable_alb_deletion_protection` |
| `envs/aws/workload` | `app_alb_enable_deletion_protection` | `enable_app_alb_deletion_protection` |

A TFC workspace variable with an old name keeps working through the alias. Rename it when convenient. `scripts/check-consistency.sh` fails when a deletion-protection input has neither the `enable_` form nor a `deprecated` marker. The `services.<name>.database.deletion_protection` object field of `app-services` and `envs/aws/workload` is unchanged.

#### `compliance.breach_notification_contacts` reaches the alert channels (aws-security, gcp-organization)

**Who:** forks that set `compliance.breach_notification_contacts`. Before, no root read the key.

**What changes:** aws-security adds one email subscription per address (`notify-dpo-<i>`) to the security-notifications topic, and the CIS alarm topic when it reuses those subscribers. gcp-organization adds one email notification channel per address to the control-plane alerts (each address once, next to `gcp.alert_emails` or `notifications.emails`). Each address gets an AWS subscription confirmation email. A production aws-security plan fails when a breach contact uses a placeholder domain (example, `.invalid`, `.localhost` or `.test`). An explicit `aws_overrides.notification_subscribers` or `gcp_overrides.alert_notification_emails` still replaces the config list, these addresses included.

With `budget_notify_alert_channels`, the extra GCP channels count toward the budget's limit of 5 channels.

#### `require_labels` is now mandatory; data classification on both clouds (CMP-10, ARC-17)

**Who:** every fork that attaches the OPA policy set (`enable_policy_sets`).
**What changes:** the `require_labels` policy in `policies/opa` is now
**mandatory** and checks four keys instead of "at least one". A listed GCP
resource (`google_storage_bucket`, `google_kms_crypto_key`, `google_project`,
`google_sql_database_instance` and the others in
`policies/opa/require_labels.rego`) must carry `managed-by`, `environment`,
`cost-center` and `owner`, and a listed AWS resource `ManagedBy`,
`Environment`, `CostCenter` and `Owner`. A violation stops the run, and the set
is not overridable. Every root already writes these keys through its provider
`default_labels` / `default_tags`, so the shipped roots pass. Code of your own
fails when it adds a provider block without the defaults, or a Cloud SQL
instance whose `settings.user_labels` lack the four keys (provider default
labels never reach `user_labels`; `gcp-workload` now passes them in its module
labels).

Other changes in the same release:

- **GCP labels.** Every GCP root's provider `default_labels` gain `cost-center`
  and `owner`, from `org.cost_center` and `org.owner` (defaults `platform` and
  `platform-team`, as on AWS), lowercased with any character other than a
  letter, digit, `_` or `-` changed to `-`. The first plan of every GCP root
  updates the labels of existing resources in place. The `gcp-projects` owner
  label on projects now follows `org.owner` too.
- **GCP data classification.** `gcp.environments.<env>.data_classification`
  (`public`, `internal` (default), `confidential` or `restricted`) is now read.
  `gcp-projects` binds the organization `data-classification` tag value of that
  name to each environment host project and publishes its ID as
  `environment_config.<env>.tag_value_ids.data_classification`. Apply
  `gcp-organization` first: it grants `projects-apply`
  `roles/resourcemanager.tagUser` on the `data-classification` tag key and on
  each environment folder, which the binding needs. A supplied organization
  contract (`organization_contract` / `gcp.contracts.organization`) must now
  list `data-classification-<value>` in `tag_values` for every value in use, or
  the `gcp-projects` plan fails and names the missing keys.
- **AWS tag policy.** The organization tag policy is built in
  `modules/aws/governance/organization-policy/main.tf` (`tag_policy_content`);
  `policies/tag-policy.json` is gone. It adds `DataClassification` with the
  four allowed values (an in-place policy update). `aws.tagging.required_for`
  (input `tag_policy_required_resource_types`, default empty) adds
  `report_required_tag_for` for the four keys. A tag policy alone never blocks
  an untagged resource. To fail plans on a missing key, set the workspace
  environment variable `TF_AWS_TAG_POLICY_COMPLIANCE=error` in
  `config/tfc-workspaces.yaml`, after you confirm in the sandbox that the plan
  and apply roles can call `tag:ListRequiredTags`.
- **AWS `DataClassification` tag.** Every AWS root adds it to its
  `default_tags`: `aws-workload-<env>` from
  `aws.workload_environments.<env>.data_classification` (variable
  `data_classification`, default `internal`), `aws-security` `confidential`,
  `aws-backup` `restricted` (it holds copies of every class), the other shared
  roots `internal`. Override a shared root with
  `default_tags = { DataClassification = "..." }`. The first plan updates the
  tags of existing resources in place.

#### `compliance_class: regulated` (CMP-7, opt-in)

**Who:** forks that mark an environment as holding regulated data. Nothing
changes for an estate without `compliance_class: regulated`; the flow-log
variables of `gcp-workload` now default to null with the same effective values
(10% sampling, 30 days). Setting `compliance_class: regulated` on a
`gcp.environments` entry makes its `gcp-workload-<env>` plan apply the
`regulated-gcp-workload` preset (enforced VPC-SC, Cloud Armor with OWASP rules,
every flow sampled, 365-day flow-log retention) and fail on a dry-run or absent
perimeter, on `production_vpc_sc_dry_run_waiver`, or on a variable that lowers
the flow-log values. Full sampling raises the Cloud Logging cost. Setting it on
an `aws.workload_environments` entry turns on the shared hub's Network Firewall
and egress gate in `aws-network` on every profile, and refuses
`egress_alert_only_waived`, `enforce_egress_allowlist = false` and
`enable_network_firewall = false`. **Before you set it:** read the VPC-SC
dry-run violation logs (GCP) and complete `aws.network.egress_domain_allowlist`
(AWS). `aws.network.vpc_endpoint_policy_mode: org_principals_and_resources`
(`aws:ResourceOrgID` on the hub endpoints) is a separate PREVIEW opt-in. See
[`docs/architecture/regulated-environments.md`](docs/architecture/regulated-environments.md).
A regulated GCP environment also fails the plan on `enable_cloud_armor = false`
or `enable_owasp_rules = false`. A regulated AWS environment also makes
`aws-security` fail the plan when the log-archive retention
(`aws_overrides.log_archive_retention_days`, else
`compliance.audit_log_retention_days`) is below 365 days: that bucket holds
the VPC flow logs.

#### `config/landing-zone.yaml` is now schema-validated (`make config-check`, CI, pre-commit)

**Who:** every fork that commits `config/landing-zone.yaml`. **Before the
merge:** run `make config-check`. It and the CI meta-lint step now validate
your `config/landing-zone.yaml` against `config/landing-zone.schema.json`, as
they already did for the example, sandbox and test fixtures. A key the schema
does not know, including a misspelled one such as `is_prodution`, now fails CI.
Fix the key. If the key is valid and the schema lacks it, report a schema gap.
A pre-commit hook checks the same file when you commit it.

#### `is_production` is required on every environment (all roots that read environments)

**Who:** every fork. **Before the apply:** add `is_production: true` or
`is_production: false` to each entry under `gcp.environments` and
`aws.workload_environments` in `config/landing-zone.yaml`, and to each entry of
tfc-admin's `environments` variable if you set it. The plan now fails, naming
each entry without it, in tfc-admin, in aws-network (unless you set
`enforce_egress_allowlist`) and in every GCP root (gcp-workload checks its own
environment). The names
`prod` and `production` no longer make an environment production on their own.
Before this change, tfc-admin and aws-network treated an unflagged `prod` as
production, gcp-workload treated any name that contains `prod` (also `nonprod`
and `preprod`) as production, and the other GCP roots treated an unflagged
environment as non-production. Check that each flag matches what you intend
before you apply.

**Auto-apply consequence (tfc-admin, policy sets on).** Before this change, an
environment without the flag kept manual confirmation: only an explicit
`is_production: false` opted its workload into auto-apply. Now that every
environment states the flag, `is_production: false` on a previously unflagged
environment (`qa`, `uat` and so on) gives its `gcp-workload-<env>` /
`aws-workload-<env>` workspace `auto_apply_run_trigger` and `queue_all_runs`
while `enable_nonprod_workload_auto_apply` is on (by default, whenever the
policy sets are on). A confirmed upstream apply then applies that workload with
no second confirmation. Set `is_production: true` on any such environment that
you want confirmed by hand, or set `enable_nonprod_workload_auto_apply = false`
on tfc-admin.

gcp-workload now also fails the plan when the gcp-projects contract
`environment_config.<env>` has no `is_production`. The gcp-projects contract
output always sets it. Add it if you supply the contract yourself
(`projects_contract` or `gcp.contracts.projects`).

#### `make plan-gcp-workload` no longer adds the example tfvars file (tooling)

`APP_VARS` is now empty unless you set it, so the target no longer passes `examples/dev.tfvars.example`. That example no longer sets `project_prefix`, `environment`, `region`, `terraform_admin_email`, `tfc_organization` or `organization_workspace_name`. Those values come from `config/landing-zone.yaml` and from the workspace variables that tfc-admin sets. If a script relied on the old default, pass `APP_VARS=<file>` yourself.

#### The release workflow uses a GitHub App (CI)

`release.yml` now mints its token from a release GitHub App instead of reading `RELEASE_PLEASE_TOKEN`. Set the variable `RELEASE_APP_ID` and the secret `RELEASE_APP_PRIVATE_KEY` in the `release` environment. The workflow has no fallback. See [CI_SECRETS.md](docs/guides/CI_SECRETS.md#release_app).

#### `make ci` runs more gates (contributors)

`make ci` now also runs `yamllint`, `markdownlint-check`, `commit-check`, `codeowners-check`, `scaffold-fixtures-check` and `opa-test`. It needs `pre-commit`, commitizen (`cz`), `opa` 1.22.2 and a fetched `origin/main`. Set `COMMIT_BASE=<ref>` to compare against another base.

#### The compute dashboard applies changes (gcp)

`compute-dashboard` no longer ignores `dashboard_json`, so tile and threshold changes now reach the dashboard. The next plan may update an existing dashboard once, to match the module.

#### Deletion guards also block replacement (gcp, aws)

The Cloud SQL and Aurora guards now also fail a plan that would replace the instance or cluster. The Aurora guard follows `deletion_protection`, and its address moves to `terraform_data.deletion_guard[0]` (a `moved` block handles this). To destroy or replace on purpose, run `terraform state rm` on the guard, then set the flag to false and apply.

#### Removed-input shims are deleted (gcp-organization, aws-security)

The inert re-declarations of the 81 removed variables, and `terraform_data.removed_inputs_guard`, are gone before v1.0 (the project is pre-1.0). A stale old variable now produces Terraform's "undeclared variable" warning instead of failing the plan. Before you upgrade, confirm that no old variable is still set, and move any you find into `gcp_overrides` or `aws_overrides`.

#### Unknown keys in map inputs fail the plan (gcp-workload, aws-network)

`app_services`, `additional_regions`, `vm_backup_schedules`, `os_patch_deployments` (gcp-workload) and `vpn` (aws-network) now reject keys their consumers do not accept, instead of dropping them silently.

#### The KMS key_names output returns full key names (gcp)

`modules/gcp/governance/kms` output `key_names` now returns the full key resource name (`projects/.../cryptoKeys/<key>`), not the short key name. Every `kms_key_name` argument needs the full form, so gcp-organization's CMEK wiring (audit logs, SCC, billing) and the net-spoke flow-logs key failed to plan before. A caller that relied on the short name should use the map key instead.

#### Security Lake creates one data lake per Region (aws-security)

The aws provider accepts one `configuration` block per data lake, so more than one enabled Region failed to plan. The first enabled Region keeps its data lake (no address change). Each other Region gets its own data lake, encrypted with its key from `additional_region_kms_key_ids` (S3-managed when absent), because a KMS key is regional.

#### Opt-in egress proxy per environment (gcp-workload, preview)

`enable_egress_proxy` (or `gcp.environments.<env>.egress_proxy: true`) sends the environment's private-tier egress through the hub Secure Web Proxy. The gcp-network-hub contract publishes the proxy's service attachment as `hub_network.egress_proxy_service_attachment`. The plan fails when the proxy is on for an environment but the hub has no proxy.

#### The `starter` profile requires a budget (aws-organization, gcp-organization)

An estate with `org.profile: starter` and no `org.monthly_budget_usd` now
**fails the plan** of aws-organization and gcp-organization
(`terraform_data.starter_requires_budget`). Set `org.monthly_budget_usd` (USD,
above 0) in `config/landing-zone.yaml`, or `monthly_budget_usd`
(aws-organization) / `monthly_budget_amount` (gcp-organization). On AWS also
keep `enable_cost_governance = true`. Then, for starter estates only:

- **aws-organization** replaces `budgets` with one `org-monthly` budget of that
  amount, alerting at 50/80/100% of actual spend and 100% forecast. The default
  `org-monthly` budget updates in place; **any other key you set in `budgets`
  is deleted**. Keep a custom budget by switching to `profile: production` or
  re-creating it outside this root.
- **gcp-organization** sets the organization budget to that amount, with
  thresholds at 50/80/100% of current spend (in-place update of the budget).

`production` estates are unchanged: `monthly_budget_usd` is ignored there, and
the GCP budget keeps its default thresholds.

#### One `notifications` section feeds the existing alert paths

New optional `notifications` in `config/landing-zone.yaml` (`emails`,
`hcp_email_user_ids`). Without it nothing changes. When set, it becomes the
fallback (an explicit variable and the specific keys `gcp.alert_emails` /
`aws.guard_alert_emails` still win):

- **gcp-organization:** the control-plane alert email channels, which are also
  attached to the organization budget (at most 5 channels; the plan fails
  above that).
- **aws-security:** `notification_subscribers` (now default `null`) becomes one
  email subscription per address on the security topic (also used by the CIS
  alarms); without the section it keeps the old placeholder. Each new address
  must confirm its SNS subscription.
- **aws-organization:** `guard_alert_emails`, budgets with empty `emails`, and
  `cost_anomaly_email` (now default `null`: the first address, else
  `finops@example.com` as before). The anomaly monitor takes one subscriber only.
- **tfc-admin:** `hcp_email_user_ids` (HCP user IDs, not addresses) adds a
  `notify-email` notification (`run:errored`, `run:needs_attention`,
  `assessment:*`) to control-plane and workload workspaces; your own
  `control_plane_notifications` / `workload_notifications` are kept.

#### Terraform 1.17

**Breaking for every fork.** Every `versions.tf` now requires
`>= 1.17, < 2.0` (CI, `.tool-versions` and `.terraform-version` pin 1.17.1).
An older CLI fails at `terraform init`.

Manual steps:

1. **Local CLI.** Install Terraform 1.17.1 (`scripts/setup.sh` reads
   `.tool-versions`). Pin it in any fork-owned pipeline that runs `terraform`.
2. **HCP Terraform workspaces.** Each workspace's `terraform_version` must
   allow 1.17. tfc-admin's `terraform_version` default moves from `~> 1.9` to
   `~> 1.17`, so apply `tfc-admin` first: it bumps every workspace it manages.
   (HCP resolves a constraint to the newest matching release, so a workspace on
   the old `~> 1.9` default may already run 1.17; the bump makes the floor
   explicit. A workspace pinned to an exact older version fails until bumped.)
   If you set `terraform_version` yourself (tfvars or a TFC variable on
   tfc-admin), raise it to `~> 1.17`. Bump by hand any workspace tfc-admin does
   not manage, including tfc-admin's own workspace when
   `manage_tfc_admin_workspace = false`.
3. **No way back.** A state written by 1.17 cannot be read by an older CLI.
   Roll the CLI forward everywhere before the first 1.17 apply.

What else changes on the next plan:

- **Deprecation warnings (no plan change).** Compatibility inputs now carry
  Terraform's `deprecated` attribute, so setting one prints a "Deprecated
  variable got a value" warning that names the replacement. Nothing else
  changes. The inputs:
  - the 81 removed variables of gcp-organization and aws-security (their
    declarations and guard were deleted in a later release; see "Removed-input
    shims are deleted");
  - `config_role_arn` and `create_config_service_linked_role` on
    `envs/aws/workload` and `modules/aws/stages/workload`. The root no longer
    passes them to the stage, which replaces the stage's warning `check`;
  - `vpn_shared_secret` on `modules/gcp/stages/net-hub` (use
    `vpn_shared_secret_wo`).

  Root-module outputs cannot be deprecated (Terraform rejects it), and a module
  output marked deprecated fails `terraform validate` on the module. The
  individual producer outputs and `guardrail_deny_policy_specs` therefore keep
  their "Deprecated" description only. `network/vpn` `shared_secret` is not
  marked either, because `stages/net-hub` always passes it, and the warning
  would then fire on every hub plan. All of them are still removed at v1.0.
- **Typed `contract` outputs (no resource change).** Each producer's
  `output "contract"` declares its exact object type. The JSON is unchanged.
  The map-valued keys (`account_ids`, `ou_ids`, `folders`, `project_ids` and
  others) are now stored as maps rather than objects. In-repo consumers already
  read them through `tomap()`. A fork root that compares a contract key with
  `==` against an object literal must compare `jsonencode()` values instead.
  If you add a key to a producer's `local.contract`, add it to the output's
  `type` too, or the conversion drops it; `make consistency` catches the
  mismatch.
- **`import` blocks stay in the roots.** `make consistency` now fails on an
  `import` block inside `modules/` or `templates/`: a module-level import is
  inherited by every caller. Put adoption `import` blocks in the root (see
  [gcp-brownfield-adoption](docs/runbooks/gcp-brownfield-adoption.md)).

#### SaaS secret bridge reads ephemerally (aws-workload-&lt;env&gt;, gcp-workload-&lt;env&gt;)

Applies to workloads with `enable_saas_secret_bridge = true`. Workloads with
the bridge off see no change and need no new token.

`data.terraform_remote_state.saas` is gone. The workload now reads the Supabase
outputs with `ephemeral "tfe_outputs" "saas"` and writes them with the existing
write-only arguments, so the service-role key and database password are no
longer stored in the workload's plan or state. The first apply drops the old
data source from state. Older state versions in HCP Terraform still hold the
values: rotate the bridged secrets
([saas-bootstrap](docs/runbooks/saas-bootstrap.md#bridging-secrets-to-a-workload-and-rotating-them))
if that history matters to you.

Before the first plan:

1. **`TFE_TOKEN` is now required** on every bridging workspace: the
   `saas-outputs-reader` team token, set as described in the runbook. Without
   it the `tfe` provider fails to configure. The bridge reads through that
   team's `read-outputs` grant, not through remote-state sharing.
2. **The version source moved.** The write-only version cannot come from an
   ephemeral read, and any non-ephemeral read of the saas workspace stores all
   of its outputs. The version therefore comes from `saas.bridge_rotation` in
   `config/landing-zone.yaml`, the same key the saas root publishes as
   `bridge_version`. A new `saas_bridge_version` variable overrides it per
   workload. If you set `bridge_rotation` as a variable on a `saas-<name>`
   workspace instead of in the config file, set the same number as
   `saas_bridge_version` on its bridging workloads.
3. **Mismatch fails the plan.** A postcondition on the ephemeral read fails
   the workload plan while the saas workspace publishes a different
   `bridge_version`. Until then, any bridging-workload run fails, by design:
   it would otherwise push the old values under the new version.
4. **Re-queue each bridging workload after `saas-<name>` applies.** No run
   trigger connects them, so after a rotation bump: apply `saas-<name>`, then
   start a run on every bridging workload by hand.
5. **Escape hatch.** For an emergency workload change while the versions
   differ, temporarily set `saas_bridge_version` on that workload to the old
   value (the one `saas-<name>` still publishes). Remove the override once
   `saas-<name>` has applied.

Workloads with the bridge off make unauthenticated discovery and ping calls to
`app.terraform.io` when their `tfe` provider configures with the placeholder
token. A fork on Terraform Enterprise sets `TFE_HOSTNAME` on those workspaces.

The plan shows no change to the secret: the version stays the same, and the
GCP secret moves to the secret-manager module's ephemeral path under the same
address. Both workload lockfiles gain `hashicorp/tfe` 0.83.0.

#### Object pass-through: `gcp_overrides` (gcp-organization) and `aws_overrides` (aws-security)

**Breaking for anyone who sets these roots' variables** in a tfvars file, a TFC
workspace variable or `config/tfc-workspaces.yaml`. The two roots that re-declared
almost every stage input now take one object each:

- `envs/gcp/organization` declares `gcp_overrides`, the gcp section of
  `modules/gcp/stages/organization` (its new `gcp` input). 46 variables moved.
- `envs/aws/security` declares `aws_overrides`, the aws section of
  `modules/aws/stages/security` (its new `aws` input). 35 variables moved.

Every key is optional. The effective object is
`merge(local.lz_<section>, { for k, v in var.<section>_overrides : k => v if v != null })`,
so precedence is unchanged: a set key > `config/landing-zone.yaml` > the stage
default. The validations moved onto the stage object; their messages name the
config key. Resource addresses do not change: the upgrade plan of an estate
whose values moved 1:1 shows no changes.

**Before the upgrade plan,** move each old variable into the override object.
For a TFC workspace variable, delete the old variable and add one HCL variable,
for example `gcp_overrides = { enable_pam = true, pam_eligible_groups = ["..."] }`.
Leave a key out to keep its config value. **An old variable that is still set
fails the plan** in this release, through `terraform_data.removed_inputs_guard`.
A later release deleted that guard and the inert declarations (see "Removed-input
shims are deleted"): after it, a stale variable only produces an "undeclared
variable" warning, so move every old variable first.

Behaviour changes to check:

- **An empty list now wins.** `alert_notification_emails = []` and
  `containment_exempt_principals = []` used to mean "fall back to the config file".
  As override keys, `[]` is a set value. Leave the key out (or null) to keep
  `gcp.alert_emails` / `notifications.emails` and `gcp.break_glass_group`.
- **The waiver follows the effective value.** gcp-organization waives production
  admin containment when the effective `enable_admin_containment` is `false`. Before,
  `gcp.admin_containment: false` waived it even when the variable said `true`.
- **Presets replace, they do not merge.** A `-var-file` sets the whole object, so
  `examples/presets/prod-gcp-organization.tfvars`, `prod-aws-security.tfvars` and
  `nonprod-aws-security.tfvars` replace your own `gcp_overrides` / `aws_overrides`.
  Copy their keys into your own object instead of stacking the files.
- **`key_policy_admin_role_name` stays a variable** on aws-security and its stage:
  `null` (legacy key-policy admin) cannot be expressed through the null-filtered merge.
- **The stage interfaces changed.** A fork that calls
  `modules/gcp/stages/organization` or `modules/aws/stages/security` from its own
  root passes the moved inputs inside `gcp = { ... }` / `aws = { ... }`. Their
  names are unchanged. gcp-organization keeps `domain`, `project_prefix`,
  `organization_name`, `billing_account(_display_name)`, `tfc_organization`,
  `environments`, `shared_iam_group_role_bindings`, `default_region`, `profile`,
  `monthly_budget_amount`, the bootstrap contract inputs, `terraform_admin_email`,
  `tfc_hostname`, `pin_wif_to_tfc_organization` and `wif_github_owner_ids`.
  aws-security keeps its org-section, tagging, credential and contract inputs.

Setting any old name below fails the plan (removed-inputs guard, removed at v1.0).

| Old `gcp-organization` variable | New key | Config key (unchanged) |
|---|---|---|
| `admin_email` | `gcp_overrides.admin_email` | `gcp.admin_email` |
| `break_glass_user` | `gcp_overrides.break_glass_user` | - |
| `organization_admin_groups` | `gcp_overrides.organization_admin_groups` | `gcp.organization_admin_groups` |
| `billing_admin_groups` | `gcp_overrides.billing_admin_groups` | `gcp.billing_admin_groups` |
| `allow_user_principals_for_break_glass` | `gcp_overrides.allow_user_principals_for_break_glass` | - |
| `allowed_regions` | `gcp_overrides.allowed_regions` | `gcp.allowed_regions` |
| `strict_folder_policy_environment_keys` | `gcp_overrides.strict_folder_policy_environment_keys` | - |
| `enforce_os_login` | `gcp_overrides.enforce_os_login` | - |
| `os_login_exempt_environment_keys` | `gcp_overrides.os_login_exempt_environment_keys` | - |
| `security_contact_email` | `gcp_overrides.security_contact_email` | - |
| `billing_contact_email` | `gcp_overrides.billing_contact_email` | - |
| `budget_currency` | `gcp_overrides.budget_currency` | - |
| `logging_project_id` | `gcp_overrides.logging_project_id` | - |
| `logging_project_number` | `gcp_overrides.logging_project_number` | - |
| `audit_soft_delete_retention_days` | `gcp_overrides.audit_soft_delete_retention_days` | - |
| `enable_control_plane_alerting` | `gcp_overrides.enable_control_plane_alerting` | - |
| `enable_cis_log_metrics` | `gcp_overrides.enable_cis_log_metrics` | - |
| `alert_notification_emails` | `gcp_overrides.alert_notification_emails` | `gcp.alert_emails / notifications.emails` |
| `alert_notification_channels` | `gcp_overrides.alert_notification_channels` | - |
| `break_glass_principal_emails` | `gcp_overrides.break_glass_principal_emails` | - |
| `custom_org_constraints` | `gcp_overrides.custom_org_constraints` | - |
| `enable_audit_bucket_lock` | `gcp_overrides.enable_audit_bucket_lock` | `gcp.enable_audit_bucket_lock` |
| `iam_deny_policies` | `gcp_overrides.iam_deny_policies` | - |
| `enable_cmek_org_policy` | `gcp_overrides.enable_cmek_org_policy` | - |
| `cmek_required_services` | `gcp_overrides.cmek_required_services` | - |
| `enable_admin_containment` | `gcp_overrides.enable_admin_containment` | `gcp.admin_containment` |
| `containment_exempt_principals` | `gcp_overrides.containment_exempt_principals` | `gcp.break_glass_group` |
| `enable_legacy_admin_folder_roles` | `gcp_overrides.enable_legacy_admin_folder_roles` | - |
| `enable_scoped_access_policies` | `gcp_overrides.enable_scoped_access_policies` | - |
| `enable_pam` | `gcp_overrides.enable_pam` | - |
| `pam_eligible_groups` | `gcp_overrides.pam_eligible_groups` | - |
| `pam_approver_groups` | `gcp_overrides.pam_approver_groups` | - |
| `pam_max_request_duration` | `gcp_overrides.pam_max_request_duration` | - |
| `guardrail_owner_mode` | `gcp_overrides.guardrail_owner_mode` | - |
| `prefer_managed_constraints` | `gcp_overrides.prefer_managed_constraints` | - |
| `enable_log_analytics` | `gcp_overrides.enable_log_analytics` | - |
| `log_analytics_retention_days` | `gcp_overrides.log_analytics_retention_days` | - |
| `enable_logging_organization_settings` | `gcp_overrides.enable_logging_organization_settings` | - |
| `logging_settings_kms_key_name` | `gcp_overrides.logging_settings_kms_key_name` | - |
| `enable_principal_access_boundary` | `gcp_overrides.enable_principal_access_boundary` | `gcp.principal_access_boundary` |
| `principal_access_boundary_allowed_resources` | `gcp_overrides.principal_access_boundary_allowed_resources` | - |
| `restrict_cloud_run_ingress` | `gcp_overrides.restrict_cloud_run_ingress` | - |
| `allowed_workload_identity_issuers` | `gcp_overrides.allowed_workload_identity_issuers` | - |
| `allowed_workload_identity_aws_accounts` | `gcp_overrides.allowed_workload_identity_aws_accounts` | - |
| `org_policy_overrides` | `gcp_overrides.org_policy_overrides` | - |
| `wif_tenant_pin_enforcement` | `gcp_overrides.wif_tenant_pin_enforcement` | - |

| Old `aws-security` variable (guarded the same way) | New key | Config key (unchanged) |
|---|---|---|
| `aws_enabled_regions` | `aws_overrides.aws_enabled_regions` | `aws.enabled_regions` |
| `log_archive_bucket_name` | `aws_overrides.log_archive_bucket_name` | `aws.log_archive_bucket_name` |
| `key_admin_arn` | `aws_overrides.key_admin_arn` | - |
| `key_admin_role_name` | `aws_overrides.key_admin_role_name` | - |
| `kms_key_user_arns` | `aws_overrides.kms_key_user_arns` | - |
| `enable_kms_protection_tag` | `aws_overrides.enable_kms_protection_tag` | - |
| `config_role_arn` | `aws_overrides.config_role_arn` | - |
| `create_config_service_linked_role` | `aws_overrides.create_config_service_linked_role` | - |
| `aggregator_role_arn` | `aws_overrides.aggregator_role_arn` | - |
| `meta_store_manager_role_arn` | `aws_overrides.meta_store_manager_role_arn` | - |
| `break_glass_role_arn` | `aws_overrides.break_glass_role_arn` | - |
| `enabled_security_services` | `aws_overrides.enabled_security_services` | - |
| `enable_security_lake` | `aws_overrides.enable_security_lake` | - |
| `config_record_all_supported` | `aws_overrides.config_record_all_supported` | - |
| `guardduty_enable_ebs_malware_protection` | `aws_overrides.guardduty_enable_ebs_malware_protection` | - |
| `enable_incident_response` | `aws_overrides.enable_incident_response` | - |
| `enable_service_quotas` | `aws_overrides.enable_service_quotas` | - |
| `notification_subscribers` | `aws_overrides.notification_subscribers` | `notifications.emails` |
| `identity_account_id` | `aws_overrides.identity_account_id` | - |
| `enable_cloudwatch_logs` | `aws_overrides.enable_cloudwatch_logs` | - |
| `cloudwatch_logs_retention_days` | `aws_overrides.cloudwatch_logs_retention_days` | - |
| `cloudwatch_logs_kms_key_arn` | `aws_overrides.cloudwatch_logs_kms_key_arn` | - |
| `cloudtrail_alarm_sns_topic_arn` | `aws_overrides.cloudtrail_alarm_sns_topic_arn` | - |
| `cloudtrail_alarm_subscribers` | `aws_overrides.cloudtrail_alarm_subscribers` | - |
| `cloudtrail_cis_alarms_excluded` | `aws_overrides.cloudtrail_cis_alarms_excluded` | - |
| `cloudtrail_s3_data_events` | `aws_overrides.cloudtrail_s3_data_events` | - |
| `cloudtrail_s3_data_events_excluded_bucket_arns` | `aws_overrides.cloudtrail_s3_data_events_excluded_bucket_arns` | - |
| `cloudtrail_lambda_data_events` | `aws_overrides.cloudtrail_lambda_data_events` | - |
| `create_break_glass` | `aws_overrides.create_break_glass` | - |
| `break_glass_role_name` | `aws_overrides.break_glass_role_name` | - |
| `break_glass_trusted_principals` | `aws_overrides.break_glass_trusted_principals` | - |
| `break_glass_mfa_max_age` | `aws_overrides.break_glass_mfa_max_age` | - |
| `break_glass_active` | `aws_overrides.break_glass_active` | - |
| `create_organization_trail` | `aws_overrides.create_organization_trail` | - |
| `cloudtrail_cloudwatch_role_arn` | `aws_overrides.cloudtrail_cloudwatch_role_arn` | - |

#### Removed: `modules/gcp/stages/host` and `modules/gcp/network/dns-records`

Both modules had no caller in this repo. `stages/host` (the deprecated network
facade) is replaced by `stages/net-hub`, `stages/dns-anchor` and
`stages/net-spoke`; `network/dns-records` duplicated `network/dns`.

No manual step for the landing-zone roots. A fork that calls either module from
its own root must move off it before taking this release: use the replacement
stages above, or declare the records through `modules/gcp/network/dns`.

#### One `contract` output per producer root

Every producer root (`aws-organization`, `aws-security`, `aws-network`,
`gcp-bootstrap`, `gcp-organization`, `gcp-projects`, `gcp-network-hub`) now
publishes one non-sensitive `contract` output: an object holding every key it
already exported. The roots in this repo, and tfc-admin's `tfe_outputs` reads,
now read only `.outputs.contract` (`.nonsensitive_values.contract`).
`scripts/check-contracts.sh` (`make consistency`, CI) enforces it.

No manual step. Upgrade apply order is unchanged.

- **Before a producer re-applies,** its state has no `contract` output yet.
  Consumers then fall back to the old individual outputs, which hold the same
  keys, so a consumer that plans first still plans with no changes.
- **The individual outputs stay** as deprecated aliases. Their descriptions say
  `Deprecated: read contract.<key>`. A consumer outside this repo should switch
  to `outputs.contract.<key>` before v1.0.
- **The `<layer>_contract` override variables share one type per upstream.**
  For example, `organization_contract` has the same type in every aws root.
  Fields that only some roots need are now `optional`. A root that needs a field
  checks it in a variable validation, and the error names the field. Existing
  overrides and `<cloud>.contracts.*` config keep working unchanged.
- **New guard resources.** aws-backup, gcp-projects, gcp-network-hub and
  gcp-workload each plan one new `terraform_data` contract guard (a create,
  with no cloud resource). It fails the plan with the missing contract field
  named, for example `ou_ids["Workloads"]` or `environment_config["<env>"]`,
  whatever the source: variable, config or remote state.
- **The gcp-organization admin-containment preconditions** moved from the
  `admin_containment_enabled` output to the `contract` output.

## Sandbox upgrade log

Copy this block once per release, fill it in from the sandbox run, and commit it
with the merge. An empty log means the release was not proven in the sandbox.

```markdown
### Sandbox upgrade log: <tag>

- Previous release (N-1): <tag>
- Sandbox applied on: <date>, by <name>

| Workspace | N-1 to N apply result | Plan summary (add/change/destroy) | Notes |
|---|---|---|---|
| <workspace> | <success / failed / skipped> | <+a ~c -d> | <link to run> |

`destroy_guard` overrides:

| Workspace | Resource | Reason | Approved by |
|---|---|---|---|
| <workspace> | <address> | <why the delete or replace is intended> | <security team member> |
```

## Legacy modes removed at v1.0

Each dual mode keeps both paths until v1.0. Migrate before then.

| Legacy mode | Replacement | Entry |
|---|---|---|
| `guardrail_deny_policy_specs` output on gcp-organization | Policies authored in `envs/gcp/guardrails` | GCP deny policies move to the security-team `gcp-guardrails` workspace |
| `guardrail_owner_mode = "organization"` (in-stage apply, `roles/iam.denyAdmin` on the organization apply SA) | `guardrail_owner_mode = "separate"` | GCP deny policies move to the security-team `gcp-guardrails` workspace |
| Workload `removed` block for `module.config_recorder`, the deprecated `config_role_arn` and `create_config_service_linked_role` inputs, and the `config_role_arn` output | The `org-config-recorders` StackSet in aws-organization | AWS Config recorders move to an aws-organization StackSet |
| Flag-off recorder path of the SCP (recorder actions in `DenyWeakenSecurityServices`) | `enable_config_recorder_scp = true` | AWS Config recorders move to an aws-organization StackSet |
| The individual cross-root outputs of the producer roots, and the consumers' fallback to them when `contract` is absent | The `contract` output (`outputs.contract.<key>`) | One `contract` output per producer root |
| `connectivity = peering` as the default hub connectivity (VPC peering from each spoke) | `connectivity = ncc`, the default from v1.0 once sandbox-proven. `peering` stays selectable. | NCC hub/spoke connectivity, opt-in |
| `deletion_protection` on `modules/gcp/network/tiered-vpc` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `deletion_protection` on `modules/gcp/stages/dns-anchor` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `deletion_protection` on `modules/gcp/stages/net-hub` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `deletion_protection` on `modules/gcp/stages/net-spoke` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `deletion_protection` on `modules/gcp/stages/environment` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `deletion_protection` on `modules/gcp/governance/private-ca` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `deletion_protection` on `modules/aws/data/rds-aurora` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `delete_protection` on `modules/aws/network/network-firewall` (deprecated alias) | `enable_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `alb_enable_deletion_protection` on `modules/aws/stages/app-services` (deprecated alias) | `enable_alb_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `app_alb_enable_deletion_protection` on `envs/aws/workload` (deprecated alias) | `enable_app_alb_deletion_protection` | Deletion-protection inputs renamed to `enable_*deletion_protection` |
| `patch_operating_system` on `modules/aws/ops/systems-manager` (deprecated, one OS) | `patch_operating_systems` (a list) | Patch Manager now installs patches |
