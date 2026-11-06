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
3. Move any `iam_deny_policies` from the gcp-organization variables to a
   committed `envs/gcp/guardrails/guardrails.auto.tfvars` (CODEOWNERS: platform +
   security; `.gitignore` exempts it). Do not set them as `gcp-guardrails`
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

### AWS management KMS access by key policy, not tags

`tfc-management-roles` no longer grants the aws-security apply role `kms:*` on
keys carrying `Workspace = aws-security` (a tag anyone with `kms:TagResource`
could plant). `CreateOwnedKeysOnly` stays, now limited to the owner tag key plus
the `tags` keys. The org trail's CloudWatch Logs CMK is instead managed through
its own key policy: a new `PipelineKeyManagement` statement
(`cloudwatch_logs_kms_key_manager_arns`, defaulting to the
`tfc-mgmt-aws-security-apply` role) grants describe/get/list, rotation,
description, tags and aliases. The account-root `kms:*` statement is kept.

**Manual step for existing estates (before applying the new
`tfc-management-roles`):** the pipeline's `kms:PutKeyPolicy` is denied, so the
new statement must be added once, by a break-glass principal (the account root
or an administrator in the management account). Without it, the next
aws-security plan/apply gets AccessDenied on the key. Substitute your values:

```sh
KEY_ID=$(aws kms describe-key --key-id alias/<trail_name>-cloudwatch --query KeyMetadata.KeyId --output text)
aws kms get-key-policy --key-id "$KEY_ID" --policy-name default --query Policy --output text > policy.json
# Edit policy.json: append this statement to "Statement" (keep the existing ones):
#   {"Sid":"PipelineKeyManagement","Effect":"Allow",
#    "Principal":{"AWS":"arn:aws:iam::<MGMT_ACCOUNT_ID>:role/tfc-mgmt-aws-security-apply"},
#    "Action":["kms:Describe*","kms:Get*","kms:List*","kms:EnableKeyRotation",
#              "kms:UpdateKeyDescription","kms:TagResource","kms:UntagResource",
#              "kms:CreateAlias","kms:UpdateAlias","kms:DeleteAlias"],
#    "Resource":"*"}
aws kms put-key-policy --key-id "$KEY_ID" --policy-name default --policy file://policy.json
```

Then upgrade `tfc-management-roles`, and confirm aws-security plans with no
changes to the key policy. Fresh estates need nothing.
