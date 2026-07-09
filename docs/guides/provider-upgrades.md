# Provider Major-Version Upgrade Posture

This guide records the repo's current stance on `google`/`google-beta` provider major
versions, what was actually tested, and the procedure for re-testing when the question
comes up again (it will — Dependabot or a contributor will eventually try to bump past
the current ceiling).

## Current constraint

All modules and environments pin:

```hcl
required_providers {
  google = {
    source  = "hashicorp/google"
    version = ">= 6.0, < 8.0"
  }
  google-beta = {
    source  = "hashicorp/google-beta"
    version = ">= 6.0, < 8.0"
  }
}
```

i.e. both provider 6.x and 7.x satisfy the constraint today.

## 2026-07-08 investigation: is provider 7.x actually compatible?

**Trigger:** commit `baa0866` disabled Dependabot for the `terraform` ecosystem because a
batch of provider-bump PRs (6.x/7.31.0 → 7.34.0) failed CI validation across ~15 modules
and both env roots. Because the constraint already permits `< 8.0`, that left a real,
unverified compatibility gap: the repo *claims* to support google provider 7.x but had
never actually confirmed it end-to-end.

**Method:** picked `modules/stages/organization/examples/basic` (the module most heavily
implicated in the failing PRs), temporarily tightened its constraint to `google ~> 7.0`
/ `google-beta ~> 7.0`, and ran `terraform init -backend=false && terraform validate`
against the newest available 7.x release at the time (**7.39.0**). Also re-ran the same
check with the CI-pinned Terraform CLI version (**1.9.8**, downloaded directly rather than
relying on whatever Terraform happens to be on a given machine — the local dev machine
used for this investigation had Terraform 1.14.3 installed, which turned out to matter,
see below).

**Result: `terraform validate` failed** under Terraform 1.9.8 with google/google-beta 7.39.0:

```text
Error: Invalid dynamic for_each value

  on ../../../../governance/billing/main.tf line 151, in resource "google_cloudfunctions2_function" "budget_notifier":
 151:       for_each = var.sendgrid_api_key_secret_id != "" ? [1] : []

Cannot use a list of number value in for_each. An iterable collection is required.
```

At face value this looks like exactly the provider-7.x incompatibility the disabled
Dependabot PRs implied. **It is not.** Further isolation (holding the Terraform CLI
version fixed at 1.9.8 and only changing the provider version) showed the identical
error reproduces with **google/google-beta 6.50.0 too** — the provider major version is
not a variable in this failure at all. Re-running the same check with a newer Terraform
CLI (1.14.3) against either provider version **passes cleanly** with zero errors.

**Conclusion: this is a Terraform-core `for_each`/type-inference behavior difference
between Terraform 1.9.8 and later Terraform releases, not a google-provider
compatibility problem.** The `for_each = <condition> ? [1] : []` idiom (a boolean-gated
`dynamic` block, used in 15+ files across this repo) is inferred as `list(number)` by
Terraform 1.9.8 in some contexts, which then fails the "must be an iterable collection"
check; later Terraform versions either infer a broader/looser type or handle the ternary
differently and do not fail. This is a **pre-existing, currently-live bug** independent
of this investigation — see the follow-up items below.

A second, unrelated cluster of failures in the same historical CI runs
(`modules/network/nat`, `modules/network/subnet`, `modules/stages/network-hub`, and
their examples) turned out to be a **different** pre-existing bug: a `validation` block
comparing a nullable variable (`max_ports_per_vm`) with `>=`/`<=` without a `== null ||`
guard, which Terraform 1.9.8 evaluates eagerly and fails with `argument must not be
null` — also reproducible independent of provider version, and also masked on any
machine running a newer local Terraform CLI.

**Why did this only surface on provider-bump PRs?** `terraform-plan.yml` validates on
pull requests. A provider-only lock-file bump (Dependabot's PRs bumped
`.terraform.lock.hcl`, not `versions.tf`) is exactly the kind of change that forces a
fresh `terraform init`/`validate` cycle without touching the `.tf` source — so these
already-broken `for_each`/null-validation expressions got re-exercised and failed, even
though no code semantically related to the PR's diff was at fault. Any other trigger for
a fresh validate (a `.tf` edit anywhere in the dependency chain, a Terraform Cloud state
refresh, a CI runner cache miss) would have surfaced the same failures just as easily.

### Verdict

- **Provider 7.x itself is compatible** with this codebase, as far as this investigation
  could determine — `terraform validate` under a modern Terraform CLI (1.14.3) passes
  cleanly against google/google-beta 7.39.0 with no code changes.
- **The constraint is being kept at `>= 6.0, < 8.0`** (no change) — there is no evidence
  provider 7.x itself requires narrowing this. Narrowing to `< 7.0` would not have fixed
  the original CI failures (they reproduce on 6.x too) and would incorrectly signal a
  provider incompatibility that doesn't exist.
- **The real, actionable defects are the two Terraform-1.9.8-specific bugs above.** These
  are tracked as separate follow-ups (see "Related defects" below) — they are unrelated
  to provider version and should be fixed independently of any future provider bump.
- Re-enabling Dependabot for the `terraform` ecosystem is still **not** recommended until
  those two bug classes are fixed repo-wide, since any lock-file-only bump (of any
  provider, any version) will keep re-triggering them and generating red, confusing PRs
  that look like provider incompatibilities but aren't.

### Related defects (tracked separately, not fixed by this task)

1. `for_each = <cond> ? [1] : []` type-inference failure under Terraform 1.9.8 —
   confirmed in `modules/governance/billing/main.tf:151`; the same idiom appears
   in ~15 files repo-wide and needs verification/fixing file-by-file (e.g. switch to
   `toset([...])` with a consistent element type).
2. Null-unsafe `validation` block comparisons under Terraform 1.9.8 — confirmed in
   `modules/network/nat/variables.tf` (`max_ports_per_vm`); needs a `var.x == null ||
   (...)` guard. `modules/network/subnet`, `modules/network/interconnect`, and
   `modules/stages/network-hub` failed in the same historical CI run and should be
   checked for the same pattern.

## How to re-test this in the future

1. Pick a representative example root (a leaf example like
   `modules/stages/organization/examples/basic` that exercises most of the module graph
   is a good choice — it will surface transitive issues from modules it depends on).
2. Get the **exact CI-pinned Terraform CLI version** (see `.tool-versions`), not whatever
   is on your PATH. A newer local Terraform can mask real CI-only failures, as happened
   here. Download it directly if needed:
   ```bash
   curl -sL -o /tmp/terraform.zip \
     "https://releases.hashicorp.com/terraform/<version>/terraform_<version>_<os>_<arch>.zip"
   unzip /tmp/terraform.zip -d /tmp/tf-pinned
   ```
3. Temporarily edit the example's `versions.tf` to pin the provider version(s) you want
   to test (e.g. `~> 7.0`), then:
   ```bash
   rm -rf .terraform .terraform.lock.hcl
   /tmp/tf-pinned/terraform init -backend=false
   /tmp/tf-pinned/terraform validate
   ```
4. If it fails, isolate whether the failure is actually provider-version-dependent by
   re-running the same steps with the provider constraint reverted to the current floor
   (e.g. `~> 6.0`) and the same pinned Terraform CLI. If the failure reproduces on both
   provider versions, it is a Terraform-CLI-version issue, not a provider compatibility
   issue — do not conflate the two (this is exactly the mistake the original disabled-
   Dependabot investigation risked making).
5. Revert any temporary `versions.tf` edits and regenerated lock files before committing
   anything — only land a real constraint change if the investigation concludes one is
   needed.
6. Update this document with the tested provider version, the Terraform CLI version used,
   and the outcome.
