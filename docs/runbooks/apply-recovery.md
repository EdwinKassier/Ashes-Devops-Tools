# Recovering a Failed or Partial Apply

**When to use:** a Terraform Cloud apply errored part-way, a run is stuck, or a
resource is in a bad state. The project's philosophy is roll-forward (fix the
config and apply again), but some situations need the steps below first. All of
these act on one workspace; know which root/workspace you are in before starting.

## 1. A half-applied run (apply errored part-way)

Terraform state records what actually got created, so the next plan converges the
rest. First:

1. Read the failed run's logs in TFC to find the resource that errored and why.
2. Fix the cause (a quota, a permission, a dependency ordering, a bad input).
3. Queue a new plan. It shows only the remaining and corrective changes. Apply it.

If a single resource blocks the whole plan, narrow the next apply to unblock it:

```bash
terraform -chdir=<root> apply -target=<blocking.resource>
```

Then remove the `-target` and apply normally to re-converge everything. Never
leave a workspace managed only through `-target`; it hides drift.

## 2. A resource created outside Terraform, or that must be re-adopted

- Created by hand (or by a half-run that did not record it): import it.

  ```bash
  terraform -chdir=<root> import <address> <cloud-id>
  ```

  Prefer an `import {}` block committed to the config so the adoption is reviewed.

- A resource is corrupt and must be rebuilt on the next apply: taint it.

  ```bash
  terraform -chdir=<root> taint <address>
  ```

  Beware `prevent_destroy` guards (the `terraform_data` deletion guards and GCP
  `deletion_policy = "PREVENT"`): a taint that forces replacement of a protected
  resource is blocked at plan time. Relax the guard deliberately first.

## 3. Rolling back to a previous state version

TFC keeps every state version. If an apply left state wrong and roll-forward is
not safe, roll the STATE back in the TFC UI (Workspace → States → a prior
version → Rollback), then plan to reconcile. Rolling back state does NOT undo
cloud changes; it only changes what Terraform believes exists, so pair it with a
plan and review the diff carefully before applying.

## 4. A stuck or stale-locked run

If a run hangs or the workspace is locked by a dead run, discard the run and
unlock the workspace in the TFC UI (Workspace → Runs → Discard; Settings →
Unlock). Confirm no apply is genuinely still in flight first, or you risk two
concurrent applies.

## When to stop and escalate

Stop and involve a second operator (and the break-glass path if guardrails block
you) when: a control-plane root (`gcp-organization`, `aws-organization`,
`aws-security`) is half-applied, a destroy is proposed on a `PREVENT`-protected or
WORM resource, or a rollback would cross the audit-logging or guardrail config.
These are the changes where a wrong recovery step is worse than the original
failure.
