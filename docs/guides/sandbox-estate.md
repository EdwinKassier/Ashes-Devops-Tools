# Sandbox estate: a second tfc-admin instance

The [sandbox E2E suites](sandbox-e2e.md) prove that single modules apply against a real
cloud. They cannot prove that an existing estate survives an upgrade. The sandbox estate
closes that gap. It is a complete second copy of the landing zone with its own HCP
Terraform organization, GCP organization and AWS organization. It applies every merge to
`main` on top of the previous `main`, so every merge is tested as an N-1 to N upgrade
before a release.

The estate is driven by two committed files:

| File | Role |
|------|------|
| [`config/sandbox/landing-zone.yaml`](../../config/sandbox/landing-zone.yaml) | The sandbox's single-source config. It uses `org.profile: starter`, the GCP `dev` environment only, the AWS `workload_dev` account only, and sets `org.monthly_budget_usd`. |
| [`config/sandbox/tfc-workspaces.yaml`](../../config/sandbox/tfc-workspaces.yaml) | Sets `landing_zone_config_path` on every sandbox workspace: `../../../config/sandbox/landing-zone.yaml` for `envs/<cloud>/<root>`, and `../../config/sandbox/landing-zone.yaml` for `envs/saas`. |

Both files ship with placeholders (`my-sandbox-org`, `REPLACE_WITH_*`, `example.com`).
Replace them before the first apply. `make config-check` validates the sandbox config
against the same schema as production.

## How the two estates stay apart

- **Separate HCP organizations.** Workspace names are the same in both estates
  (`gcp-organization`, `aws-workload-dev`, and so on). They never collide, because each
  estate lives in its own HCP organization.
- **Per-estate trigger patterns.** tfc-admin derives the estate's config paths from its
  own `landing_zone_config_path` and `workspace_variables_file` (output
  `estate_config_trigger_patterns`):
  - Production (`config/landing-zone.yaml`, the default) adds `config/landing-zone.yaml`
    and its `workspace_variables_file` (default `config/tfc-workspaces.yaml`) to every
    workspace's trigger patterns, as exact paths.
  - The sandbox (`config/sandbox/landing-zone.yaml`) adds `config/sandbox/**`. A
    `workspace_variables_file` outside that directory is added as its own pattern.
  - A relative path that leaves the repository fails the plan, because it cannot become
    a trigger pattern.

  The existing `<working_dir>/**` and module-domain patterns stay. Editing one estate's
  YAML therefore never queues the other estate's runs. A module or root change queues both.
- **Separate cloud organizations.** The GCP roots are organization-scoped, because folders,
  org policies and deny policies attach at the org node. The sandbox therefore needs its
  own GCP organization, on a separate Cloud Identity domain such as
  `sandbox.example.com`. The sandbox folder tree (shared plus `dev`) is created inside that
  organization. The AWS roots likewise need their own AWS organization with its own
  management account.

## Stand-up

### 1. The second HCP organization

1. Create a new HCP Terraform organization, for example `my-sandbox-org`. Put its name in
   `org.tfc.organization` in `config/sandbox/landing-zone.yaml`.
2. Connect the same VCS repository, so the sandbox tracks the same `main` as production.
   Set `org.tfc.vcs_repo` to the connection's IDs.
3. Create teams that mirror production: platform, control-plane approvers, and security.
   You pass their IDs to the sandbox tfc-admin.
4. Hand-create the sandbox `tfc-admin` workspace with working directory `envs/tfc-admin`,
   just as in production ([bootstrap runbook](../runbooks/bootstrap.md#creating-and-wiring-the-tfc-workspaces-tfc-admin-two-pass)).
   Set these workspace variables:

   | Variable | Value |
   |----------|-------|
   | `TFE_TOKEN` (env, sensitive) | A token for the **sandbox** organization only |
   | `landing_zone_config_path` | `../../config/sandbox/landing-zone.yaml` |
   | `workspace_variables_file` | `../../config/sandbox/tfc-workspaces.yaml` |
   | `auto_apply_on_merge` (HCL) | `true` |
   | `security_team_id` | The sandbox security team's ID |

   These variables live on the hand-created workspace, not in the committed config. That
   way the production tfc-admin, which reads the default paths, can never pick them up.

### 2. The GCP sandbox organization and the AWS sandbox organization

- **GCP:** create the sandbox Cloud Identity domain and its GCP organization, plus a
  billing account (or sub-account) for the sandbox. Then fill in the `gcp.*` placeholders.
  The landing zone creates its folders, projects and policies inside that organization.
- **AWS:** create a new AWS organization from a dedicated management account, following
  [AWS bootstrap phase 0](../runbooks/aws-bootstrap.md). Fill in the `aws.*` placeholders.
  Every account root email must be a real, unique, deliverable address. The
  `example.com` placeholders are rejected.

### 3. Phase 0, then the remote flip

Phase 0 is the same as production:

1. Apply the sandbox tfc-admin (pass 1). It keeps the default
   `workspace_execution_modes = { gcp-bootstrap = "local" }`, so `gcp-bootstrap` starts in
   **local** execution.
2. Apply `gcp-bootstrap` **locally**, as the sandbox's human admin, against the sandbox
   organization. A local run ignores workspace variables, so pass the sandbox config
   yourself:

   ```bash
   export TF_CLOUD_ORGANIZATION=my-sandbox-org
   terraform -chdir=envs/tfc-admin output -raw gcp_bootstrap_tfvars > envs/gcp/bootstrap/tfc-workspaces.auto.tfvars
   terraform -chdir=envs/gcp/bootstrap apply \
     -var landing_zone_config_path=../../../config/sandbox/landing-zone.yaml
   ```

   This is the only local apply against a GCP root that the repo allows.
3. Pass 2: wire the dynamic credentials (`gcp_bootstrap_outputs_from_tfc = true`) and
   **flip** `workspace_execution_modes` to `{}` on the sandbox tfc-admin. `gcp-bootstrap`
   then runs remotely like every other workspace.
4. Apply the AWS phase 0 and the remaining layers in the documented order. From then on,
   merges apply on their own.

## Auto-apply on merge

`auto_apply_on_merge = true` sets `auto_apply` and `auto_apply_run_trigger` on every
sandbox workspace **except `tfc-admin` and `gcp-guardrails`** (output
`never_auto_apply_workspaces`). Those two always wait for a human confirmation.

- A merge queues a VCS run on every workspace whose path-filtered triggers match. Those
  runs start **concurrently** and apply in **no fixed order**: a downstream workspace can
  apply before its upstream does.
- Each successful apply then fires the run triggers along the root DAG, so every
  downstream workspace runs again after its upstream has applied. The estate converges
  through these triggered reruns, not through the first wave of VCS runs.
- A downstream failure is therefore **expected** on a merge that changes an upstream
  contract (a new output, or a renamed one), and the upstream's run trigger retries it.
  Only a failure that persists after the triggered rerun is a real upgrade failure. To
  avoid the noise, sequence a contract-changing merge by hand: apply the upstream
  workspace first, then let the triggers carry it down.
- A no-change upstream apply fires no run trigger, and a local-execution apply fires none
  either.

**Never enable `auto_apply_on_merge` in production.** It auto-applies the
root-of-trust workspaces: `aws-organization`, and `gcp-bootstrap` once it has been
flipped to remote execution. A bad merge would then change the organization, the SCPs and
the automation identities with no human confirmation. Only `tfc-admin` and
`gcp-guardrails` are excluded. Production leaves the variable at its default, `false`.

## Budget and who owns the bill

`org.monthly_budget_usd` (300 in the placeholder) is the monthly ceiling for the whole
sandbox estate. The budget alerts that consume it are wired by Task 2.10. Until then,
create a billing budget by hand on the sandbox GCP billing account and in AWS Budgets on
the sandbox management account.

The **platform team owns the sandbox bill**. It is a platform cost centre
(`cost_center: platform-sandbox`), not charged back to any workload team. The `starter`
profile keeps the idle cost low, because it drops Network Firewall, Security Lake, Macie and
record-all Config. Every preventive control stays.

## Teardown

The sandbox is meant to live for as long as the repository does. If you retire it:

- **Accounts and projects are retained shells.** AWS accounts are removed from the
  organization, not closed (the `account` module default is
  `close_on_deletion = false`). GCP foundation projects carry
  `deletion_policy = "PREVENT"`, and KMS keyrings cannot be deleted. Expect empty,
  retained shells, and close them by hand later if you need to. See the
  [GCP teardown](../runbooks/teardown.md) and [AWS teardown](../runbooks/aws-teardown.md)
  runbooks for the reverse-order destroy.
- Delete the sandbox HCP organization last, after its state is no longer needed.
- A fork that does not run a sandbox can delete `config/sandbox/`. Delete the
  `sandbox_config_files_plan` run in `envs/tfc-admin/tests/sandbox.tftest.hcl` with it,
  because that run plans the committed sandbox files. See
  [`config/sandbox/README.md`](../../config/sandbox/README.md).
