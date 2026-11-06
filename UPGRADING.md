# Upgrading

Manual steps and behaviour changes to check when you merge a new release into a
fork. Newest first.

## Unreleased

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
