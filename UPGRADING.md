# Upgrading

Manual steps and behaviour changes to check when you merge a new release into a
fork. Newest first.

## Unreleased

### GCP deny policies move to the security-team `gcp-guardrails` workspace

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
3. Move any `iam_deny_policies` from the gcp-organization variables to the
   gcp-guardrails variables.
4. In `gcp-guardrails`, adopt each existing policy instead of creating it. The
   create would fail with 409. Run the import as the security team with an
   `import` block in a reviewed PR, or once from the workspace:
   `terraform import 'module.guardrails.module.iam_deny.google_iam_deny_policy.this["contain-admin-identity"]' 'cloudresourcemanager.googleapis.com%2Forganizations%2F<ORG_ID>/contain-admin-identity'`.
5. Queue a run on `gcp-guardrails`; the security team confirms it. Expect an
   in-place update of the tag condition (namespaced IDs, see above).

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

### GitHub workload identity: exact-match owner pin, ref/env pins in bindings

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
- `services[*].github.ref` and `.environment` must match `^[A-Za-z0-9_./-]+$`,
  and `environment` may not be `-` (the value a token without an environment
  claim maps to).

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
