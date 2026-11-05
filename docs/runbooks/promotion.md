# Runbook: Promoting Changes from Dev to Prod

**When to use:** you want a predictable, gated path to move a change (a new service
team, an infrastructure setting, a workload image) from `dev` through `staging` to
`prod`.

**Risk:** Low. Promotion changes config and applies one environment at a time.

---

## The model

Each environment is a separate Terraform Cloud workspace over the same root code:

```text
gcp-workload-dev  ->  gcp-workload-staging  ->  gcp-workload-prod
```

The code in `envs/gcp/workload` is identical across environments. What differs is:

- The workspace variable `environment` (`dev`, `staging`, `prod`).
- The per-environment tfvars file (`examples/<env>.tfvars`).
- The per-environment config in `environment_config` (region, CIDR, folder, host
  project), read from the `gcp-projects` remote state.

Promotion is therefore not a code merge between branches. It is applying the same
code to the next environment's workspace, after the change is proven in the
previous one. One commit on `main` is the single source of truth; the environments
differ only by their inputs.

## What gets promoted

| Change | How it promotes |
|--------|-----------------|
| A service team | Add the team's entry to the next environment's `service_teams` map (see [service-team-onboarding.md](service-team-onboarding.md)). |
| An infrastructure setting (a flag, a CIDR, a policy) | Set it in the next environment's tfvars, or in `environment_config` for per-environment values. |
| A new environment | Follow [add-environment.md](add-environment.md) to create the workspace and `environments` entry first. |
| A workload container image | The delivery pipeline deploys per environment; see [../guides/deploying-a-service.md](../guides/deploying-a-service.md). |

## The ordered flow

1. **Change `dev`.** Edit `examples/dev.tfvars` (or the shared code). Open a pull
   request. CI runs `fmt`, `validate`, `lint`, `tfsec`, `checkov`, and
   `terraform test`.
2. **Merge and apply `dev`.** After merge, the `gcp-workload-dev` workspace plans.
   Review the plan and apply it in Terraform Cloud.
3. **Verify in `dev`.** Confirm the change is healthy (resources created, the
   service reachable, no alerts firing) before promoting.
4. **Promote to `staging`.** Make the same tfvars change for `staging`, open a PR,
   merge, then apply the `gcp-workload-staging` workspace.
5. **Verify in `staging`.**
6. **Promote to `prod`.** Repeat for `prod`. The `prod` workspace apply is the
   final gate.

Each step is a separate, reviewable change. A problem found in `staging` stops the
promotion before it reaches `prod`.

## Recommended gates (admin-controlled)

These are opt-in controls the platform admin configures. None is created by this
repository, because they are organization policy, not Terraform state.

- **Terraform Cloud run approval.** Set each workspace to require manual apply (not
  auto-apply). The `tfc-admin` root sets `auto_apply = false` by default
  (`modules/tfc/workspace`), so every apply needs a human approval.
- **GitHub environment protection.** Define `dev`, `staging`, and `prod` as GitHub
  environments with required reviewers on `staging` and `prod`. A delivery workflow
  that targets a protected environment then waits for an approver.
- **Branch protection on `main`.** Require the PR review and the CI checks to pass
  before merge, so no change reaches any environment unreviewed.
- **Separate approvers per tier.** Restrict who can approve `prod` applies to a
  smaller group than `dev`.

## Rollback

Promotion is roll-forward: to undo a change in an environment, revert the tfvars
change for that environment and apply again. For a half-applied run, see
[apply-recovery.md](apply-recovery.md). Because environments are applied
independently, a rollback in `prod` does not touch `dev` or `staging`.
