# Runbook — Adopt an Existing AWS Organization (Brownfield)

`aws-organization` normally **creates** the organization, the SRA OU tree and the foundational
accounts. Most enterprises already have an organization, so a greenfield apply fails with
`AlreadyInOrganizationException`, `DuplicateOrganizationalUnitException` or a duplicate account
email. This runbook imports what exists instead.

> **Status: not yet validated against a live organization.** The import addresses are covered by
> `terraform validate`, and the inputs are covered by tests. Mock providers cannot import, so run
> the first plan against a non-production organization and read it in full.

## 1. Decide what Terraform will own

| Existing thing | Adopt it? | Notes |
|---|---|---|
| The organization (`o-…`) | Yes, always | Adopting it sets `feature_set = ALL` and the repo's enabled policy types and trusted services. |
| OUs whose names match the SRA tree (`Security`, `Infrastructure`, `Workloads`, `Workloads/Prod`, …) | Yes | The keys must match `top_level_ous` / `child_ous`. |
| OUs with other names | No | Leave them unmanaged, or add them to `top_level_ous` / `child_ous` first, then adopt them. |
| Foundational accounts (log archive, security tooling, …) | Yes, if they exist | The key must match `aws.accounts` and the email must match the account's root email exactly, or the plan replaces the account. |
| Existing SCPs / RCPs | No | The repo attaches its own policy set. Detach or retire the old SCPs once the plan's guardrails are in place, and keep `FullAWSAccess` attached throughout. |

## 2. Collect the IDs

```bash
aws organizations describe-organization --query 'Organization.Id' --output text
root=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations list-organizational-units-for-parent --parent-id "$root" \
  --query 'OrganizationalUnits[].[Name,Id]' --output text
aws organizations list-accounts --query 'Accounts[].[Name,Id,Email]' --output text
```

## 3. Declare them in `config/landing-zone.yaml`

```yaml
aws:
  adopt:
    organization_id: o-abcd123456
    ou_ids:
      Security: ou-abcd-11111111
      Workloads: ou-abcd-22222222
      Workloads/Prod: ou-abcd-33333333
    account_ids:
      log_archive: "111111111111"
      security_tooling: "222222222222"
```

The `adopt_existing` variable overrides this config key. Quote account IDs so YAML keeps leading
zeros.

## 4. Plan, review, apply

Run the `aws-organization` plan, from TFC or locally per the [bootstrap runbook](aws-bootstrap.md).
Expect `import` actions for each declared resource and **in-place updates** where the live settings
differ: enabled policy types, trusted service principals, account tags. Stop if the plan shows:

- **an account `must be replaced`:** the email or name in `aws.accounts` differs from the live
  account. Fix the config. A replace would try to close and recreate the account.
- **an OU `must be replaced`:** its parent differs from the SRA tree. Move the OU in AWS, or
  change `child_ous`.
- **`FullAWSAccess` detached:** never detach it. The repo's SCPs are deny-lists that rely on it.

After the apply, the `aws.adopt` block can stay. Import blocks for resources already in state are
no-ops.

## 5. Control Tower coexistence

If the organization is governed by **AWS Control Tower**:

- **Do not adopt Control Tower-managed OUs or accounts into Terraform**, such as `Security`,
  `Sandbox` and the Log Archive / Audit accounts. Control Tower owns their lifecycle and drift
  detection, and a second owner causes fights. Leave them out of `adopt` and out of the managed
  OU tree. Point `aws-security` at the existing log-archive and audit accounts through
  `organization_contract`.
- **Keep Control Tower's own SCPs and controls.** This repo's SCPs, RCPs and declarative policies
  are additive. Review them against the Control Tower mandatory controls for conflicts before
  attaching them to Control Tower-registered OUs. The region-restriction SCP in particular
  overlaps the Control Tower Region deny control. Enable one, not both.
- **Account vending stays with Control Tower Account Factory (AFT).** Use this repo's
  `aws-workload` and `app-services` layers inside the vended accounts, and bind them to TFC with
  `tfc_workspace_bindings`.
- **Choose one org-wide CloudTrail.** If Control Tower runs the organization trail, set the
  `aws-security` trail off rather than running two org trails.

## Rollback

Imports change nothing in AWS. If the first plan looks wrong, remove the `aws.adopt` entries.
To make Terraform forget an adopted resource without destroying it, use a `removed` block with
`lifecycle { destroy = false }`. Never `terraform destroy` an adopted organization.
