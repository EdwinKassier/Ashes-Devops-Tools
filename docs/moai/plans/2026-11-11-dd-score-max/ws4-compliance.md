# WS4 Controls a regulated auditor can test: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or build to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every control the compliance docs claim is true in code, testable with
`mock_provider`, switchable from `config/landing-zone.yaml`, and mapped to the
framework clauses an auditor will test (SOC 2, ISO 27001:2022, NIST 800-53 rev5,
PCI DSS v4.0.1, HIPAA Security Rule, DORA, FedRAMP Moderate). Where the repo
cannot provide a control, the docs say so plainly.

**Architecture:** One new top-level config section, `compliance`, carries the
estate-wide compliance knobs (audit retention, framework list, backup copy). One
new per-environment attribute, `compliance_class: standard | regulated`, turns
the strict network, backup and encryption posture on for the environments that
hold regulated data, without changing any other environment. Every behaviour
change that cannot be undone (vault lock, bucket lock, Object Lock retention) is
gated on that config, never on a silent default, and has an `UPGRADING.md` note.
Existing mechanisms are reused: the `enforce_egress_allowlist` production gate,
the YAML preset loader in `envs/gcp/workload`, the `require_labels` OPA policy,
the `state-backup.yml` WORM targets, the `security-notifications` SNS topic, the
LOG-05 control-plane alerts and `config/tfc-workspaces.yaml`.

**Tech Stack:** Terraform 1.17.1 (`mock_provider`, `override_module`,
`terraform_data` preconditions, `check` blocks), hashicorp/aws 6.72.0,
hashicorp/google 8.x, OPA/Rego v1, JSON Schema (`config/landing-zone.schema.json`),
GitHub Actions (one new scheduled workflow), Markdown.

Test command used in every task (from the repo root):

```bash
TF=/private/tmp/claude-501/-Users-edwinkassier-Desktop-Ashes-Ashes-Devops-Tools--claude-worktrees-enterprise-devops-audit-949b65/50c7eb6b-1026-4421-925b-256b9cc0fb04/scratchpad/tf/terraform
make test TEST_DIRS=<dir> TERRAFORM=$TF
```

Gates after each task: `make docs`, `make consistency`, `make links`,
`make config-check` (when the schema or a fixture changed), `make fmt-check`.

---

## Findings covered

| Finding | Severity | Verified state in this tree | Task(s) |
|:--|:--|:--|:--|
| CMP-1 backups not WORM in practice; restore testing tests an empty vault | Critical | VALID. Member vaults use `aws/backup` with no lock (`modules/aws/stages/organization/backup_role.tf:16-24`). `backup-policy.json` has no `copy_actions`. The backup account sits in the Infrastructure OU, so the Workloads-OU policy never writes to the central vault, and `backup-vault/main.tf:66-80` restore-tests only that vault and only EBS. Extra: Aurora is never tagged `backup = true`, so the BACKUP_POLICY selects no Aurora cluster. | T1, T2, T3, T4 |
| CMP-2 audit retention fixed | Critical | VALID. `envs/gcp/organization/main.tf:39-99` never sets `audit_log_retention_days`. `modules/aws/stages/security/main.tf:184-196` never sets `retention_days` on `log_archive_bucket`. | T5, T6 |
| CMP-3 patching installs nothing; AL2 default | High | VALID. `modules/aws/ops/systems-manager/main.tf` has a baseline and inventory only; `variables.tf:57-60` defaults to `AMAZON_LINUX_2` (end of support 2026-06-30). | T7 |
| CMP-4 GCP audit store not WORM, no SoD, false checkov text | High | VALID. Lock and `logging_project_id` are commented out in `examples/presets/prod-gcp-organization.tfvars:35-40`; skip text at `cloud-audit-logs/main.tf:85-91` and `SECURITY.md:52` call the sink "tamper-evident". | T8 |
| CMP-5 no GCP TLS floor | High | VALID in effect. `app-ingress` already has `ssl_policy_id` (`variables.tf:62-66`) but nothing creates an SSL policy and `stages/environment/main.tf:388-400` never passes one. No `gcp.restrictTLSVersion`. | T9 |
| CMP-6 `secops@example.com` default | High | VALID. `envs/aws/security/config.tf:76-79`; asserted by `envs/aws/security/tests/contract.tftest.hcl:229-237`. | T10 |
| CMP-7 enforcement passes traffic; no regulated zone | High | PARTLY VALID. The firewall part is overstated: `envs/aws/network/config.tf:83` plus `modules/aws/stages/network-hub/main.tf:409-423` already fail the plan for alert-only egress when `org.profile = production` and any AWS workload env is production. Valid residuals: endpoint policy `Action="*"` (`vpc-endpoints/main.tf:29-42`), GCP VPC-SC dry-run is only a `check` (`envs/gcp/workload/main.tf:302-307`), flow logs 10% / 30 days (`envs/gcp/workload/variables.tf:265-286`), no regulated class. | T11 |
| CMP-8 no GCP backup vault; Cloud SQL backups can leave region | High | VALID. `modules/gcp/data/cloud-sql/main.tf:129-130` passes `null`; no `google_backup_dr_*` resource anywhere. | T12 |
| CMP-9 no regulatory breach-notification runbook | High | VALID. `docs/runbooks/incident-response.md` is GCP containment only. | T13 |
| ARC-8 single region, no RTO/RPO, no Aurora/Backup cross-region copy | High | VALID. | T2 (DR-region copy), T14 |
| CMP-10 tag policy cannot require tags; no classification key | Medium | VALID. `tag-policy.json` has 3 keys, no `report_required_tag_for`; GCP `data-classification` tag (`stages/organization/main.tf:250`) is never bound. | T15 |
| ARC-17 cost tags not enforced | Medium | VALID. `require_labels` is advisory and accepts any one label; GCP default labels carry no cost-center or owner. | T15 |
| CMP-11 SaaS residency, subprocessors, BAA, exit plan | Medium | VALID. `envs/saas/config.tf:41` and `vercel_serverless_region` are never checked against any allowed list. | T16 |
| CMP-12 GCP KMS placement and protection; Cloud SQL CMEK optional | Medium | VALID. | T17 |
| CMP-13 no TFC audit-trail export | Medium | VALID. | T18 |
| CMP-14 Developer (PowerUserAccess) assignable to prod | Medium | VALID. `envs/aws/identity/variables.tf:86-88`, no assignment guard. | T19 |
| CMP-15 no FIM; SCC tier not activated | Medium | VALID, but SCC tier activation has no Terraform API (console or billing step); FIM needs a host agent. Docs-only plus honest matrix rows. | T20 |
| CMP-16 no MFA detective control | Medium | PARTLY INVALID. AWS already alerts on console sign-in without MFA (`security-notifications/main.tf:61`, matrix LOG-10) and CIS 4.2 (LOG-09); Security Hub CIS v3.0.0 checks IAM user MFA. Residual: Identity Center MFA settings and Google 2-Step Verification have no Terraform API. Docs-only. | T20 |
| CMP-17 stale matrix citations | Low | VALID. Missing paths: `policies/declarative-ec2.json`, `policies/rcp-data-perimeter.json.tftpl`, `policies/tag-policy.json`, `network/network-firewall` (GCP row); two rows share ID `IAM-14`; LOG-08 says retention is "not exposed". | T21 |
| CMP-18 stale `SECURITY.md` | Low | VALID. Lines 52, 57, 63, 64. | T21 |
| CMP-19 wrong PCI retention text | Low | VALID. `modules/gcp/stages/organization/variables.tf:546-555` says "12 months online + 12 months archival"; PCI DSS v4.0.1 10.5.1 is 12 months with the latest 3 months immediately available. "FedRAMP requires 3 years" is also wrong (OMB M-21-31: 12 months active plus 18 months cold). | T5, T21 |
| CMP-20 mixed EU/US defaults | Low | VALID. `net-spoke/variables.tf:320,323` default `US`; `net-hub`, `net-spoke`, `dns-anchor` `region` default `us-central1`; org stage `allowed_regions` default mixes EU and US. | T21 |
| Sovereign partition (audit fitness table) | n/a | VALID and wider than stated: the canonical AWS region regex `^[a-z]{2}-[a-z]+-[1-9][0-9]?$` also rejects GovCloud (`us-gov-west-1`) and the EU sovereign region (`eusc-de-east-1`); 23 ARN regexes in 12 files accept only `aws`, `aws-us-gov`, `aws-cn`. | T22 |
| Framework crosswalks | n/a | NIST rev5 present in the matrix; PCI, HIPAA, DORA, FedRAMP Moderate absent. | T23 |

## Decisions needed

| # | Decision | Options | Recommendation |
|:--|:--|:--|:--|
| D1 | How the member vaults get a key that supports cross-account copy | (a) new CMK-encrypted member vault next to the old one, BACKUP_POLICY retargeted; (b) replace the existing vault's key in place | **(a).** `EncryptionKeyArn` on `AWS::Backup::BackupVault` forces replacement, and a same-name replacement with `DeletionPolicy: Retain` fails. (a) is additive; old recovery points age out under their 365-day lifecycle. |
| D2 | Where central copies land | (a) a new CMK-encrypted, Compliance-locked copy vault in the backup account; (b) the existing `org-backup-vault` | **(a).** The existing vault uses the AWS-managed key by default (`stages/backup/variables.tf:11-14`) and changing its key forces replacement of a vault that may already be locked. A new name avoids both. The old vault stays empty and is documented. |
| D3 | Default for `compliance.backup.copy_to_central_vault` | off everywhere / on for `production` profile | **Off by default; `make init --profile production` scaffolds it `true`.** The Compliance-mode lock on the copy vault is irreversible after `changeable_for_days`, so it must be an explicit config line the owner commits. |
| D4 | Patch install default | install on all managed instances weekly / scan only | **Install on, `RebootIfNeeded`, Sunday 03:00 UTC, 10% concurrency**, opt out per stage with `enable_patch_install = false`. PCI DSS 6.3.3 needs critical patches within one month; scan-only does not meet it. |
| D5 | `gcp.restrictTLSVersion` default | on for production profile / opt-in only | **On when `org.profile = production`**, opt out with `gcp_overrides.restrict_tls_versions = false`. It blocks TLS 1.0 and 1.1 to Google APIs only, which current client libraries do not use. |
| D6 | Regulated class shape | per-environment attribute / separate preset files | **Per-environment `compliance_class`** in both `gcp.environments.<env>` and `aws.workload_environments.<env>`. One switch the auditor can read in the config file; the GCP side expands it into the existing YAML preset loader. |
| D7 | Tag enforcement strength | `require_labels` stays advisory / becomes mandatory | **Mandatory for the four keys every root already sets through `default_tags` / `default_labels`** (after T15 adds `cost-center` and `owner` to GCP labels). A mandatory policy with near-zero false positives is evidence; an advisory one is not. |
| D8 | VPC endpoint policy in regulated estates | keep `aws:PrincipalOrgID` only / add `aws:ResourceOrgID` | **Add `aws:ResourceOrgID` only when a regulated AWS environment exists**, with an exception list for AWS-owned resources (for example `s3` buckets that serve Amazon Linux repositories). This can break package installs; it must be sandbox-proven before it is the regulated default. |
| D9 | TFC audit-trail export destination | the existing state-backup WORM buckets / a new SIEM | **Reuse the `state-backup.yml` S3 and GCS targets with a `tfc-audit/` prefix.** They already have Object Lock or a locked retention policy and OIDC roles. |

---

## Shared config contract (used by several tasks)

Added to `config/landing-zone.schema.json` (top level, `additionalProperties: false`):

```json
"compliance": {
  "type": "object",
  "description": "Estate-wide compliance settings. Absent = today's behaviour.",
  "properties": {
    "frameworks": {
      "type": "array",
      "items": { "type": "string", "enum": ["soc2", "iso27001", "nist_800_53", "pci_dss", "hipaa", "dora", "nis2", "gdpr", "fedramp_moderate"] },
      "uniqueItems": true
    },
    "audit_log_retention_days": { "type": "integer", "minimum": 1, "maximum": 36500 },
    "backup": {
      "type": "object",
      "properties": {
        "copy_to_central_vault": { "type": "boolean" },
        "copy_retention_days": { "type": "integer", "minimum": 1 },
        "dr_region": { "type": "string", "pattern": "^([a-z]{2}|eusc)(-[a-z]+){1,2}-[1-9][0-9]?$" }
      },
      "additionalProperties": false
    },
    "breach_notification_contacts": { "type": "array", "items": { "type": "string" } }
  },
  "additionalProperties": false
}
```

Per-environment additions (inside the existing `additionalProperties` objects of
`gcp.environments` and `aws.workload_environments`):

```json
"compliance_class": { "type": "string", "enum": ["standard", "regulated"] },
"data_classification": { "type": "string", "enum": ["public", "internal", "confidential", "restricted"] }
```

Framework retention floors (days), defined once per root in `config.tf` as
`local.retention_floor_days` and kept identical by a new canonical-string check in
`scripts/check-consistency.sh` (same pattern as the region regex check at line 13):

```hcl
retention_floor_days = { pci_dss = 365, hipaa = 2190, fedramp_moderate = 913, soc2 = 0, iso27001 = 0, nist_800_53 = 0, dora = 0, nis2 = 0, gdpr = 0 }
```

Sources stated in the variable descriptions: PCI DSS v4.0.1 req. 10.5.1 (12
months, 3 months immediately available); HIPAA 45 CFR 164.316(b)(2)(i) (6 years
for required documentation, the common reading applied to audit logs; confirm
with counsel); OMB M-21-31 (12 months active plus 18 months cold storage), which
FedRAMP Rev5 AU-11 references. DORA, NIS2, GDPR, SOC 2 and ISO set no fixed
number; GDPR storage limitation (Art. 5(1)(e)) argues against keeping logs that
hold personal data longer than needed.

Example YAML added to `config/landing-zone.example.yaml` (after `notifications`):

```yaml
# compliance: estate-wide compliance knobs. Absent = today's behaviour.
# compliance:
#   frameworks: [soc2, pci_dss]            # raises the audit-retention floor
#   audit_log_retention_days: 400          # GCP audit bucket and AWS log archive
#   backup:
#     copy_to_central_vault: true          # IRREVERSIBLE lock on the copy vault (UPGRADING.md)
#     copy_retention_days: 365
#     dr_region: eu-west-1                 # must be in aws.allowed_regions
#   breach_notification_contacts: [dpo@my-org.example.com]
```

Fixtures: `tests/fixtures/landing-zone.compliance.yaml` in
`envs/gcp/organization/tests/fixtures/`, `envs/aws/security/tests/fixtures/`,
`envs/aws/backup/tests/fixtures/` and `envs/aws/organization/tests/fixtures/`, each
a minimal valid file plus the `compliance` block used by that root's test. A
negative fixture `config/tests/bad_compliance_framework.yaml` (framework
`sox`) proves the enum rejects unknown frameworks (the `config-check` negative
loop at `Makefile:338-341`).

---

## Task 1: CMP-1a. CMK member vault and cross-account copy prerequisites (aws-organization)

**Files:**
- Modify: `modules/aws/stages/organization/backup_role.tf:16-52` (template), `:54-96` (new DR StackSet)
- Modify: `modules/aws/stages/organization/variables.tf:420-450` (new inputs after `member_backup_vault_name`)
- Modify: `envs/aws/organization/config.tf`, `envs/aws/organization/main.tf:45-47`, `envs/aws/organization/variables.tf`
- Test: `modules/aws/stages/organization/tests/plan_assertions.tftest.hcl`, `modules/aws/stages/organization/tests/variables_validation.tftest.hcl`, `envs/aws/organization/tests/config.tftest.hcl`

Existing-mechanism check: `grep -rn "aws_backup_global_settings\|aws_backup_vault_policy\|copy_action" modules envs` returns nothing. The deny-tamper SCP protects KMS keys tagged `protected = "true"` (`scp-deny-tamper.json.tftpl:175-221`); the new key uses that tag, so its policy is set once at `CreateKey` and only break-glass can change it. `DenyDataPerimeterTagTampering` (`scp-baseline.json.tftpl:57-92`) only matches `dp:*` tags, so `kms:CreateKey` with `protected` is allowed for the StackSet execution role.

- [ ] **Step 0: Land the config contract.** Add the whole `compliance` block and the two per-environment keys from "Shared config contract" to `config/landing-zone.schema.json`, the commented example to `config/landing-zone.example.yaml`, and the negative fixture. Run `make config-check` (expect the negative fixture rejected, everything else valid). Commit: `feat(config): compliance section and per-environment compliance_class / data_classification keys`. Every later task reads these keys, and `scripts/check-config-schema-coverage.sh` fails if a root reads a key the schema lacks.

- [ ] **Step 1: Write the failing tests** (append to `plan_assertions.tftest.hcl`)

```hcl
# CMP-1: a CMK-encrypted member vault (cross-account copy needs a customer
# managed key on the source vault) is added next to the AWS-managed one.
run "member_backup_vault_cmk" {
  command = plan

  variables {
    member_backup_vault_encryption = "cmk"
    backup_copy_account_id         = "444444444444"
  }

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVaultCmk.Properties.BackupVaultName == "org-backup-vault-cmk" &&
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVaultCmk.Properties.EncryptionKeyArn["Fn::GetAtt"][0] == "MemberBackupVaultKey"
    )
    error_message = "the cmk mode must add org-backup-vault-cmk encrypted with the StackSet's own key."
  }

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVault.Properties.BackupVaultName == "org-backup-vault"
    )
    error_message = "the original AWS-managed vault must stay in the template (its recovery points cannot be moved)."
  }

  assert {
    condition = (
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVaultKey.Properties.EnableKeyRotation == true &&
      contains([for t in jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVaultKey.Properties.Tags : "${t.Key}=${t.Value}"], "protected=true") &&
      jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVaultKey.DeletionPolicy == "Retain"
    )
    error_message = "the member backup key must rotate, carry the deny-tamper protection tag and be retained."
  }

  assert {
    condition = (
      contains(
        [for s in jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources.MemberBackupVaultKey.Properties.KeyPolicy.Statement : s.Sid],
        "BackupAccountCopy"
      ) &&
      aws_cloudformation_stack_set.backup_service_role[0].parameters["BackupAccountId"] == "444444444444"
    )
    error_message = "the key policy must let the backup account use the key for copy jobs, through the BackupAccountId parameter."
  }
}

run "member_backup_vault_default_unchanged" {
  command = plan

  assert {
    condition     = !contains(keys(jsondecode(aws_cloudformation_stack_set.backup_service_role[0].template_body).Resources), "MemberBackupVaultCmk")
    error_message = "the default (aws_managed) must leave the StackSet template as it is today."
  }
}

run "member_backup_dr_vault" {
  command = plan

  variables {
    member_backup_vault_encryption = "cmk"
    backup_copy_account_id         = "444444444444"
    member_backup_dr_region        = "eu-west-1"
  }

  assert {
    condition = (
      aws_cloudformation_stack_set_instance.member_backup_dr_vault[0].stack_set_instance_region == "eu-west-1" &&
      !contains(keys(jsondecode(aws_cloudformation_stack_set.member_backup_dr_vault[0].template_body).Resources), "BackupServiceRole")
    )
    error_message = "the DR-region StackSet must create only the key and vault (IAM roles are global and already exist)."
  }
}
```

Append to `variables_validation.tftest.hcl`:

```hcl
run "rejects_malformed_backup_account" {
  command = plan

  variables {
    member_backup_vault_encryption = "cmk"
    backup_copy_account_id         = "12345"
  }

  expect_failures = [var.member_backup_vault_encryption]
}

run "rejects_unknown_vault_encryption" {
  command = plan

  variables {
    member_backup_vault_encryption = "sse"
  }

  expect_failures = [var.member_backup_vault_encryption]
}

run "rejects_dr_region_outside_allowed_regions" {
  command = plan

  variables {
    member_backup_vault_encryption = "cmk"
    backup_copy_account_id         = "444444444444"
    member_backup_dr_region        = "ap-south-1"
  }

  expect_failures = [var.member_backup_dr_region]
}
```

- [ ] **Step 2: Run, expect failure**

`make test TEST_DIRS=modules/aws/stages/organization TERRAFORM=$TF`
Expected: `Reference to undeclared input variable "member_backup_vault_encryption"` in every new run.

- [ ] **Step 3: Implement**

`variables.tf` (after `member_backup_vault_name`):

```hcl
variable "member_backup_vault_encryption" {
  description = "Key for the member-account backup vault. aws_managed (default): today's single vault on the aws/backup key. cmk: the StackSet also creates a rotating customer managed key (tagged protected = true, so only break-glass can change its policy or delete it) and a second vault, <member_backup_vault_name>-cmk, encrypted with it. Cross-account copy to the central vault needs the cmk vault. The original vault is kept: its recovery points cannot be moved."
  type        = string
  default     = "aws_managed"
  nullable    = false

  validation {
    condition     = contains(["aws_managed", "cmk"], var.member_backup_vault_encryption)
    error_message = "member_backup_vault_encryption must be aws_managed or cmk."
  }

  validation {
    condition     = var.member_backup_vault_encryption != "cmk" || (var.backup_copy_account_id == null ? contains(keys(var.accounts), "backup") : can(regex("^[0-9]{12}$", var.backup_copy_account_id)))
    error_message = "member_backup_vault_encryption = cmk needs the backup account: an accounts[\"backup\"] entry, or a 12-digit backup_copy_account_id."
  }
}

variable "backup_copy_account_id" {
  description = "12-digit ID of the backup account allowed to use the member backup key for cross-account copy jobs. Null derives it from accounts[\"backup\"] when that account exists."
  type        = string
  default     = null
}

variable "member_backup_dr_region" {
  description = "Optional second region for a member-account DR vault (key and vault only, no IAM). The BACKUP_POLICY copies each recovery point there (aws-backup compliance.backup.dr_region). Must be in allowed_regions, or the region SCP blocks the copy job."
  type        = string
  default     = null

  validation {
    condition     = var.member_backup_dr_region == null || (var.member_backup_vault_encryption == "cmk" && contains(var.allowed_regions, coalesce(var.member_backup_dr_region, "-")))
    error_message = "member_backup_dr_region needs member_backup_vault_encryption = cmk and must be one of allowed_regions."
  }
}
```

(`var.allowed_regions` is the existing stage input that renders the region SCP; confirm its name with `grep -n 'variable "allowed_regions"' modules/aws/stages/organization/variables.tf` before writing.)

`backup_role.tf`, replace the `member_backup_vault_resource` local and add the key:

```hcl
locals {
  # A conditional, not coalesce(): the account module's ID is unknown at plan,
  # and an explicit value must stay known.
  backup_copy_account_id = var.backup_copy_account_id != null ? var.backup_copy_account_id : try(module.account["backup"].account_id, "000000000000")

  member_backup_key_resource = {
    MemberBackupVaultKey = {
      Type                = "AWS::KMS::Key"
      DeletionPolicy      = "Retain"
      UpdateReplacePolicy = "Retain"
      Properties = {
        Description       = "AWS Backup member vault key: cross-account copy to the central backup account (managed by aws-organization)."
        EnableKeyRotation = true
        KeyPolicy = {
          Version = "2012-10-17"
          Statement = [
            {
              Sid       = "AccountAdministration"
              Effect    = "Allow"
              Principal = { AWS = { "Fn::Sub" = "arn:$${AWS::Partition}:iam::$${AWS::AccountId}:root" } }
              Action    = "kms:*"
              Resource  = "*"
            },
            {
              Sid       = "BackupAccountCopy"
              Effect    = "Allow"
              Principal = { AWS = { "Fn::Sub" = "arn:$${AWS::Partition}:iam::$${BackupAccountId}:root" } }
              Action    = ["kms:Decrypt", "kms:DescribeKey", "kms:CreateGrant", "kms:ReEncrypt*", "kms:GenerateDataKey*"]
              Resource  = "*"
            },
          ]
        }
        Tags = [{ Key = "protected", Value = "true" }]
      }
    }
  }

  member_backup_vault_cmk_resource = {
    MemberBackupVaultCmk = {
      Type                = "AWS::Backup::BackupVault"
      DeletionPolicy      = "Retain"
      UpdateReplacePolicy = "Retain"
      Properties = {
        BackupVaultName  = "${var.member_backup_vault_name}-cmk"
        EncryptionKeyArn = { "Fn::GetAtt" = ["MemberBackupVaultKey", "Arn"] }
      }
    }
  }

  member_backup_vault_resource = var.create_member_backup_vault ? merge(
    {
      MemberBackupVault = {
        Type                = "AWS::Backup::BackupVault"
        DeletionPolicy      = "Retain"
        UpdateReplacePolicy = "Retain"
        Properties          = { BackupVaultName = var.member_backup_vault_name }
      }
    },
    var.member_backup_vault_encryption == "cmk" ? merge(local.member_backup_key_resource, local.member_backup_vault_cmk_resource) : {},
  ) : {}

  backup_parameters = var.member_backup_vault_encryption == "cmk" ? {
    BackupAccountId = { Type = "String", AllowedPattern = "^[0-9]{12}$" }
  } : {}
}
```

Add `Parameters = local.backup_parameters` to `backup_service_role_template` (only when non-empty: `merge({ AWSTemplateFormatVersion = ..., Description = ..., Resources = ... }, length(local.backup_parameters) > 0 ? { Parameters = local.backup_parameters } : {})`), and on `aws_cloudformation_stack_set.backup_service_role`:

```hcl
  parameters = var.member_backup_vault_encryption == "cmk" ? { BackupAccountId = local.backup_copy_account_id } : {}
```

DR StackSet (new, same file):

```hcl
resource "aws_cloudformation_stack_set" "member_backup_dr_vault" {
  count = var.create_backup_service_role && var.member_backup_dr_region != null ? 1 : 0

  name             = "${var.backup_service_role_stack_set_name}-dr-vault"
  description      = "AWS Backup DR-region key and vault in every Workloads-OU account (cross-region copy target)."
  permission_model = "SERVICE_MANAGED"
  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "AWS Backup DR-region vault (managed by aws-organization)."
    Parameters               = local.backup_parameters
    Resources                = merge(local.member_backup_key_resource, local.member_backup_vault_cmk_resource)
  })
  parameters = { BackupAccountId = local.backup_copy_account_id }

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }

  managed_execution {
    active = true
  }

  lifecycle {
    ignore_changes = [administration_role_arn]
  }
}

resource "aws_cloudformation_stack_set_instance" "member_backup_dr_vault" {
  count = length(aws_cloudformation_stack_set.member_backup_dr_vault)

  stack_set_name            = aws_cloudformation_stack_set.member_backup_dr_vault[0].name
  stack_set_instance_region = var.member_backup_dr_region
  retain_stack              = false

  deployment_targets {
    organizational_unit_ids = [module.organization.ou_ids["Workloads"]]
  }
}
```

Root wiring, `envs/aws/organization/config.tf` `cfg`:

```hcl
    backup_copy_to_central_vault = try(tobool(local.lz.compliance.backup.copy_to_central_vault), null)
    backup_dr_region             = try(tostring(local.lz.compliance.backup.dr_region), null)
```

and effective locals: `member_backup_vault_encryption = coalesce(var.member_backup_vault_encryption, local.cfg.backup_copy_to_central_vault == true ? "cmk" : null, "aws_managed")`, `member_backup_dr_region = var.member_backup_dr_region != null ? var.member_backup_dr_region : local.cfg.backup_dr_region`. New root variables `member_backup_vault_encryption` and `member_backup_dr_region` default `null`; pass both in `main.tf:45-47`.

Root test, `envs/aws/organization/tests/config.tftest.hcl` (reuse the file's mocks):

```hcl
run "compliance_backup_selects_cmk_vaults" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
  }

  assert {
    condition     = local.member_backup_vault_encryption == "cmk" && local.member_backup_dr_region == "eu-west-1"
    error_message = "compliance.backup.copy_to_central_vault and dr_region must reach the organization stage."
  }
}
```

- [ ] **Step 4: Run, expect pass**

`make test TEST_DIRS="modules/aws/stages/organization envs/aws/organization" TERRAFORM=$TF`. Expected: all runs pass, including the existing `backup_service_role_stack_set` run (default template unchanged).

- [ ] **Step 5: Docs**
  - `make docs` (READMEs of the stage and root).
  - `UPGRADING.md` under `## Unreleased` / `### AWS`:

    > **AWS Backup member vaults (opt-in, CMP-1).** `compliance.backup.copy_to_central_vault: true` (or `member_backup_vault_encryption = "cmk"`) adds a customer managed key and a second vault, `<member_backup_vault_name>-cmk`, to every Workloads-OU account through the existing StackSet. The old vault is kept with its recovery points. The key is tagged `protected = true`: after it exists, only break-glass can change its policy or schedule its deletion (deny-tamper SCP), so a later StackSet change to the key policy fails unless it runs as break-glass. Apply `aws-organization` before `aws-backup`.

- [ ] **Step 6: Commit**

```bash
git add modules/aws/stages/organization envs/aws/organization UPGRADING.md
git commit -m "feat(aws-backup): CMK member vault and DR-region vault for cross-account copy (CMP-1)"
```

---

## Task 2: CMP-1b and ARC-8. BACKUP_POLICY copy actions, a locked central copy vault, cross-account settings

**Files:**
- Modify: `modules/aws/backup/backup-org-policy/main.tf`, `variables.tf`; delete `policies/backup-policy.json` (replaced by `jsonencode`)
- Modify: `modules/aws/backup/backup-vault/main.tf`, `variables.tf`, `outputs.tf`
- Modify: `modules/aws/stages/backup/main.tf`, `variables.tf`, `outputs.tf`
- Modify: `modules/aws/iam/tfc-management-roles/main.tf:297-336` (aws-backup apply statements)
- Modify: `envs/aws/backup/config.tf`, `main.tf:40-63`, `variables.tf`
- Test: `modules/aws/backup/backup-org-policy/tests/plan_assertions.tftest.hcl`, `modules/aws/backup/backup-vault/tests/plan_assertions.tftest.hcl`, `modules/aws/stages/backup/tests/plan_assertions.tftest.hcl`, `modules/aws/iam/tfc-management-roles/tests/plan_assertions.tftest.hcl`, `envs/aws/backup/tests/config.tftest.hcl`

Lock-out check: the aws-backup management apply role allows only Organizations backup-policy actions (`tfc-management-roles/main.tf:297-336`). `aws_backup_global_settings` runs in the management account, so the role needs `backup:UpdateGlobalSettings` and `backup:DescribeGlobalSettings`; the plan role needs `backup:DescribeGlobalSettings` (it is in `ReadOnlyAccess`). The backup-account side runs as the StackSet `tfc-apply` under `tfc-apply-boundary`, which has no `backup:*` deny (`grep -rn backup modules/aws/iam/tfc-oidc-baseline` is empty).

- [ ] **Step 1: Write the failing tests**

`backup-org-policy/tests/plan_assertions.tftest.hcl`:

```hcl
run "copy_actions_rendered" {
  command = plan

  variables {
    backup_role_arn   = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id      = "ou-abcd-1example"
    backup_vault_name = "org-backup-vault-cmk"
    retention_days    = 400
    copy_actions = [
      { destination_vault_arn = "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault", delete_after_days = 400 },
      { destination_vault_arn = "arn:aws:backup:eu-west-1:$account:backup-vault:org-backup-vault-cmk", delete_after_days = 35 },
    ]
  }

  assert {
    condition = (
      jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.copy_actions["arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault"].target_backup_vault_arn["@@assign"] == "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault" &&
      jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.copy_actions["arn:aws:backup:eu-west-1:$account:backup-vault:org-backup-vault-cmk"].lifecycle.delete_after_days["@@assign"] == "35"
    )
    error_message = "each copy action must render under rules.daily.copy_actions keyed by its destination vault ARN."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.lifecycle.delete_after_days["@@assign"] == "400"
    error_message = "retention_days must drive the daily rule lifecycle (it was hard-coded to 365)."
  }
}

run "no_copy_actions_by_default" {
  command = plan

  variables {
    backup_role_arn = "arn:aws:iam::123456789012:role/OrgBackupRole"
    target_ou_id    = "ou-abcd-1example"
  }

  assert {
    condition     = !can(jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.copy_actions)
    error_message = "the default policy must not carry copy_actions (unchanged behaviour)."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.backup.content).plans.default.rules.daily.lifecycle.delete_after_days["@@assign"] == "365"
    error_message = "the default retention must stay 365 days."
  }
}
```

`backup-vault/tests/plan_assertions.tftest.hcl`:

```hcl
run "copy_in_policy_and_restore_types" {
  command = plan

  variables {
    vault_name                     = "org-backup-copy-vault"
    allow_copy_from_organization_id = "o-abc1234567"
    restore_testing_resource_types = ["EBS", "Aurora", "RDS", "S3", "DynamoDB", "EFS"]
    restore_testing_plan_name      = "org_restore_test_copy"
  }

  assert {
    condition = (
      jsondecode(aws_backup_vault_policy.copy_in[0].policy).Statement[0].Action == "backup:CopyIntoBackupVault" &&
      jsondecode(aws_backup_vault_policy.copy_in[0].policy).Statement[0].Condition.StringEquals["aws:PrincipalOrgID"] == "o-abc1234567"
    )
    error_message = "the copy vault must accept CopyIntoBackupVault from the organization only."
  }

  assert {
    condition     = toset(keys(aws_backup_restore_testing_selection.this)) == toset(["EBS", "Aurora", "RDS", "S3", "DynamoDB", "EFS"])
    error_message = "restore testing must select every listed resource type, not only EBS."
  }

  assert {
    condition     = aws_backup_restore_testing_selection.this["Aurora"].protected_resource_arns == toset(["*"])
    error_message = "non-EBS restore selections must select all protected resources of the type in the vault."
  }
}

run "no_restore_testing_when_disabled" {
  command = plan

  variables {
    create_restore_testing = false
  }

  assert {
    condition     = length(aws_backup_restore_testing_plan.this) == 0 && length(aws_backup_restore_testing_selection.this) == 0
    error_message = "create_restore_testing = false must drop the plan and selections."
  }
}
```

Existing runs in that file address `aws_backup_restore_testing_selection.this` without a key: update them to `["EBS"]` (the default list keeps today's EBS selection, now keyed).

`stages/backup/tests/plan_assertions.tftest.hcl`:

```hcl
run "central_copy_wiring" {
  command = apply

  variables {
    enable_central_copy   = true
    organization_id       = "o-abc1234567"
    backup_account_id     = "444444444444"
    copy_vault_kms_key_arn = "arn:aws:kms:eu-west-2:444444444444:key/11111111-2222-3333-4444-555555555555"
    dr_region             = "eu-west-1"
  }

  assert {
    condition = output.copy_destination_vault_arns == [
      "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault",
      "arn:aws:backup:eu-west-1:$account:backup-vault:org-backup-vault-cmk",
    ]
    error_message = "the stage must copy every recovery point to the locked central copy vault and to the member DR vault."
  }

  assert {
    condition     = output.policy_target_vault_name == "org-backup-vault-cmk"
    error_message = "with central copy on, the BACKUP_POLICY must write to the CMK member vault."
  }

  assert {
    condition     = jsondecode(aws_backup_global_settings.this[0].global_settings["isCrossAccountBackupEnabled"]) == true
    error_message = "cross-account backup must be enabled in the management account."
  }
}

run "central_copy_off_by_default" {
  command = apply

  assert {
    condition     = output.copy_destination_vault_arns == [] && length(aws_backup_global_settings.this) == 0
    error_message = "the default stage must not copy or touch global settings."
  }
}
```

(The existing `override_module` blocks for `module.backup_vault` and `module.backup_org_policy` stay; add one for `module.copy_vault` with `outputs = { vault_arn = "arn:aws:backup:eu-west-2:444444444444:backup-vault:org-backup-copy-vault" }`.)

`tfc-management-roles/tests/plan_assertions.tftest.hcl`:

```hcl
run "aws_backup_role_can_enable_cross_account_backup" {
  command = plan

  assert {
    condition = contains(
      flatten([for s in jsondecode(output.apply_policies["aws-backup"]).Statement : s.Action if s.Sid == "BackupGlobalSettings"]),
      "backup:UpdateGlobalSettings"
    )
    error_message = "the aws-backup apply role must be able to set isCrossAccountBackupEnabled."
  }
}
```

(`output.apply_policies` is what the existing run `apply_policies_are_least_privilege` already reads.)

- [ ] **Step 2: Run, expect failure**

`make test TEST_DIRS="modules/aws/backup/backup-org-policy modules/aws/backup/backup-vault modules/aws/stages/backup modules/aws/iam/tfc-management-roles" TERRAFORM=$TF`
Expected: undeclared variables `copy_actions`, `retention_days`, `allow_copy_from_organization_id`, `enable_central_copy`; missing `Sid == "BackupGlobalSettings"`.

- [ ] **Step 3: Implement**

`backup-org-policy/variables.tf`:

```hcl
variable "retention_days" {
  description = "Days the daily rule keeps each recovery point in the member vault (lifecycle delete_after_days)."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}

variable "copy_actions" {
  description = "Copy each daily recovery point to these vaults. destination_vault_arn may use $account and $region (Organizations backup policy variables). Empty (default) = no copy."
  type = list(object({
    destination_vault_arn = string
    delete_after_days     = number
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for c in var.copy_actions : can(regex("^arn:aws[a-z-]*:backup:[a-z0-9$-]+:([0-9]{12}|\\$account):backup-vault:[A-Za-z0-9_-]{2,50}$", c.destination_vault_arn)) && c.delete_after_days >= 1])
    error_message = "copy_actions entries need a backup-vault ARN (account may be $account) and delete_after_days >= 1."
  }
}
```

`backup-org-policy/main.tf` (replaces the `templatefile` call; `var.content` override kept):

```hcl
locals {
  daily_rule = merge(
    {
      schedule_expression      = { "@@assign" = "cron(0 5 ? * * *)" }
      target_backup_vault_name = { "@@assign" = var.backup_vault_name }
      lifecycle                = { delete_after_days = { "@@assign" = tostring(var.retention_days) } }
    },
    length(var.copy_actions) == 0 ? {} : {
      copy_actions = {
        for c in var.copy_actions : c.destination_vault_arn => {
          target_backup_vault_arn = { "@@assign" = c.destination_vault_arn }
          lifecycle               = { delete_after_days = { "@@assign" = tostring(c.delete_after_days) } }
        }
      }
    },
  )

  policy_document = jsonencode({
    plans = {
      default = {
        regions = { "@@assign" = [var.default_region] }
        rules   = { daily = local.daily_rule }
        selections = {
          tags = {
            backup = {
              iam_role_arn = { "@@assign" = var.backup_role_arn }
              tag_key      = { "@@assign" = "backup" }
              tag_value    = { "@@assign" = ["true"] }
            }
          }
        }
      }
    }
  })
}

resource "aws_organizations_policy" "backup" {
  name    = var.policy_name
  type    = "BACKUP_POLICY"
  content = var.content != "" ? var.content : local.policy_document
  tags    = var.tags
}
```

Update the `default_region` description (drop "No cross-region copy_action is configured").

`backup-vault/variables.tf` additions: `create_restore_testing` (bool, default `true`), `restore_testing_resource_types` (list(string), default `["EBS"]`, validation against `["EBS", "EC2", "RDS", "Aurora", "S3", "DynamoDB", "EFS", "FSx", "DocumentDB", "Neptune"]`), `allow_copy_from_organization_id` (string, default `null`, validation `^o-[a-z0-9]{10,32}$`).

`backup-vault/main.tf`: add `count = var.create_restore_testing ? 1 : 0` to the role, its attachment and the plan (`include_vaults` unchanged); replace the selection:

```hcl
resource "aws_backup_restore_testing_selection" "this" {
  for_each = var.create_restore_testing ? toset(var.restore_testing_resource_types) : toset([])

  name                      = "${var.restore_testing_selection_name}_${lower(each.key)}"
  restore_testing_plan_name = aws_backup_restore_testing_plan.this[0].name
  protected_resource_type   = each.key
  iam_role_arn              = local.restore_testing_role_arn

  # EBS keeps today's tag selection; every other type selects all protected
  # resources of that type in the vault ("*").
  protected_resource_arns = each.key == "EBS" ? null : ["*"]

  dynamic "protected_resource_conditions" {
    for_each = each.key == "EBS" ? [1] : []
    content {
      string_equals {
        key   = "aws:ResourceTag/${var.restore_testing_tag_key}"
        value = var.restore_testing_tag_value
      }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.restore_testing]
}

resource "aws_backup_vault_policy" "copy_in" {
  count             = var.allow_copy_from_organization_id != null ? 1 : 0
  backup_vault_name = aws_backup_vault.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOrganizationCopyIn"
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "backup:CopyIntoBackupVault"
      Resource  = "*"
      Condition = { StringEquals = { "aws:PrincipalOrgID" = var.allow_copy_from_organization_id } }
    }]
  })
}
```

Keep existing state in place: the EBS selection keeps its current name (set the
`name` expression to `each.key == "EBS" ? var.restore_testing_selection_name : "${var.restore_testing_selection_name}_${lower(each.key)}"`,
because a name change replaces the selection), and add:

```hcl
moved {
  from = aws_backup_restore_testing_selection.this
  to   = aws_backup_restore_testing_selection.this["EBS"]
}

moved {
  from = aws_backup_restore_testing_plan.this
  to   = aws_backup_restore_testing_plan.this[0]
}
```

The restore-testing role already uses `count`; its condition becomes
`var.create_restore_testing && local.create_restore_testing_role`, so its address
does not move.

`stages/backup/variables.tf` additions: `enable_central_copy` (bool, false), `organization_id` (string, null), `backup_account_id` (string, null), `copy_vault_name` (string, `"org-backup-copy-vault"`), `copy_vault_kms_key_arn` (string, null), `copy_vault_key_admin_arn` (string, null), `copy_retention_days` (number, 365), `retention_days` (number, 365), `dr_region` (string, null), `dr_copy_retention_days` (number, 35), `member_vault_name` (string, null: derived). Validation: `!var.enable_central_copy || (var.organization_id != null && can(regex("^[0-9]{12}$", coalesce(var.backup_account_id, "-"))) && (var.copy_vault_kms_key_arn != null || var.copy_vault_key_admin_arn != null))`.

`stages/backup/main.tf` additions:

```hcl
locals {
  member_vault_name = coalesce(var.member_vault_name, var.enable_central_copy ? "${var.vault_name}-cmk" : var.vault_name)

  central_copy_vault_arn = "arn:${var.partition}:backup:${var.aws_region}:${coalesce(var.backup_account_id, "000000000000")}:backup-vault:${var.copy_vault_name}"
  copy_actions = concat(
    var.enable_central_copy ? [{ destination_vault_arn = local.central_copy_vault_arn, delete_after_days = var.copy_retention_days }] : [],
    var.enable_central_copy && var.dr_region != null ? [{ destination_vault_arn = "arn:${var.partition}:backup:${var.dr_region}:$account:backup-vault:${var.vault_name}-cmk", delete_after_days = var.dr_copy_retention_days }] : [],
  )
}

# Organization-wide cross-account backup (management account). Without it, AWS
# Backup rejects copy jobs to another account in the organization.
resource "aws_backup_global_settings" "this" {
  count = var.enable_central_copy ? 1 : 0
  global_settings = {
    "isCrossAccountBackupEnabled" = "true"
  }
}

module "copy_vault_key" {
  source = "../../data/kms-key"
  count  = var.enable_central_copy && var.copy_vault_kms_key_arn == null ? 1 : 0
  providers = {
    aws = aws.backup
  }

  alias                 = "backup-copy-vault"
  org_id                = var.organization_id
  management_account_id = var.management_account_id
  key_admin_arn         = var.copy_vault_key_admin_arn
  key_account_id        = var.backup_account_id
}

# The locked WORM destination for every member recovery point (CMP-1). A new
# vault, not the existing one: changing a vault's key forces replacement.
module "copy_vault" {
  source = "../../backup/backup-vault"
  count  = var.enable_central_copy ? 1 : 0
  providers = {
    aws = aws.backup
  }

  vault_name                      = var.copy_vault_name
  kms_key_arn                     = coalesce(var.copy_vault_kms_key_arn, try(module.copy_vault_key[0].key_arn, null))
  min_retention_days              = var.min_retention_days
  max_retention_days              = var.max_retention_days
  changeable_for_days             = var.changeable_for_days
  allow_copy_from_organization_id = var.organization_id
  restore_testing_plan_name       = "org_restore_test_copy"
  restore_testing_resource_types  = ["EBS", "EC2", "RDS", "Aurora", "S3", "DynamoDB", "EFS"]
  restore_testing_role_arn        = var.restore_testing_role_arn
  permissions_boundary_arn        = local.backup_boundary_arn
}
```

In `module "backup_vault"` add `create_restore_testing = !var.enable_central_copy` (the old vault receives nothing, so testing it proves nothing). In `module "backup_org_policy"` set `backup_vault_name = local.member_vault_name`, `retention_days = var.retention_days`, `copy_actions = local.copy_actions`, and add `module.copy_vault` and `aws_backup_global_settings.this` to `depends_on`. Read the `kms-key` module's `variables.tf:22-147` before writing `module "copy_vault_key"`: if its key policy does not grant `backup.amazonaws.com` usage through `via_services`, pass `via_services = ["backup"]` in the form that file documents. New outputs: `copy_destination_vault_arns = [for c in local.copy_actions : c.destination_vault_arn]`, `policy_target_vault_name = local.member_vault_name`, `copy_vault_arn = try(module.copy_vault[0].vault_arn, null)`. The stage needs `management_account_id` (new variable, null) for the key module.

`tfc-management-roles/main.tf`, add to the `"aws-backup"` list:

```hcl
      {
        # Organization-wide cross-account backup (CMP-1 copy to the central vault).
        Sid      = "BackupGlobalSettings"
        Effect   = "Allow"
        Action   = ["backup:UpdateGlobalSettings", "backup:DescribeGlobalSettings"]
        Resource = "*"
      },
```

`envs/aws/backup`: `cfg` reads `compliance.backup.copy_to_central_vault`, `.copy_retention_days`, `.dr_region` and `compliance.audit_log_retention_days` is NOT used here (backup retention is a separate decision). Pass `enable_central_copy`, `organization_id = local.org.organization_id`, `management_account_id = local.org.management_account_id`, `backup_account_id = lookup(local.org.account_ids, "backup", null)`, `copy_retention_days`, `dr_region`. Root precondition (in the existing `organization_contract_guard`, or a new `terraform_data.backup_copy_guard`): `!local.enable_central_copy || contains(keys(local.org.account_ids), "backup")`. A config test in `envs/aws/backup/tests/config.tftest.hcl`:

```hcl
run "compliance_backup_section_turns_on_copy" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
  }

  assert {
    condition     = local.enable_central_copy == true && local.dr_region == "eu-west-1" && local.copy_retention_days == 400
    error_message = "compliance.backup.* must feed the backup root."
  }
}
```

- [ ] **Step 4: Run, expect pass**

Same command as Step 2, plus `make test TEST_DIRS=envs/aws/backup TERRAFORM=$TF`.

- [ ] **Step 5: Tag Aurora for the BACKUP_POLICY**

`modules/aws/data/rds-aurora`: add variable `enable_org_backup` (bool, default `true`) and merge `{ backup = "true" }` into the cluster tags when true. Test in `modules/aws/data/rds-aurora/tests/plan_assertions.tftest.hcl`:

```hcl
run "cluster_tagged_for_org_backup" {
  command = plan

  assert {
    condition     = aws_rds_cluster.this.tags["backup"] == "true"
    error_message = "Aurora clusters must carry backup = true so the org BACKUP_POLICY selects them."
  }
}
```

(Use the file's existing `variables` block; the cluster is `aws_rds_cluster.this`, `rds-aurora/main.tf:44`.) Adding a tag is an in-place update.

- [ ] **Step 6: Docs**
  - `UPGRADING.md` `### AWS`:

    > **Central backup copy (opt-in, CMP-1, IRREVERSIBLE lock).** `compliance.backup.copy_to_central_vault: true` creates `org-backup-copy-vault` in the backup account with a Compliance-mode Vault Lock. After `changeable_for_days` (default 3) the lock cannot be removed by anyone, including root, and recovery points cannot be deleted before `min_retention_days`. Check `min_retention_days` and `max_retention_days` before the apply. The BACKUP_POLICY then writes to `<vault_name>-cmk` in each member account and copies every recovery point to the copy vault (and to the member DR vault when `compliance.backup.dr_region` is set). Cross-account copy also needs the source resource keys to be shareable: Aurora and RDS encrypted with a CMK need a key policy that lets the backup account use the key; EBS volumes on the `aws/ebs` AWS-managed key cannot be copied across accounts, so set `account-baseline` `kms_key_arn` to a CMK first. Apply order: `aws-organization` (Task 1), then `aws-backup`. Restore testing moves to the copy vault; the old central vault stays empty.
  - `docs/known-gaps.md` A5: replace "there is no `copy_actions` stanza" with the shipped opt-in and the remaining validation items (copy job success for each resource type, restore testing metadata for RDS and Aurora, cross-account copy for EBS on AWS-managed keys).

- [ ] **Step 7: Commit**

```bash
git add modules/aws/backup modules/aws/stages/backup modules/aws/iam/tfc-management-roles modules/aws/data/rds-aurora envs/aws/backup UPGRADING.md docs/known-gaps.md
git commit -m "feat(aws-backup): copy recovery points to a locked central vault and a DR region (CMP-1, ARC-8)"
```

---

## Task 3: CMP-1c. Restore-testing evidence and backup alarms

**Files:**
- Modify: `modules/aws/backup/backup-vault/main.tf`, `variables.tf`
- Test: `modules/aws/backup/backup-vault/tests/plan_assertions.tftest.hcl`

Existing-mechanism check: `security-notifications` already fans EventBridge rules into a KMS-encrypted SNS topic (`modules/aws/security/security-notifications/main.tf:55-72`), but it runs in the security-tooling account, and Backup events are emitted in the backup account. A vault notification to an SNS topic in the backup account is the smallest correct step; forwarding to the security topic is a follow-up.

- [ ] **Step 1: Failing test**

```hcl
run "vault_notifications_for_failed_jobs" {
  command = plan

  variables {
    notification_topic_arn = "arn:aws:sns:eu-west-2:444444444444:backup-events"
  }

  assert {
    condition = toset(aws_backup_vault_notifications.this[0].backup_vault_events) == toset([
      "BACKUP_JOB_FAILED", "COPY_JOB_FAILED", "RESTORE_JOB_FAILED", "S3_BACKUP_OBJECT_FAILED", "S3_RESTORE_OBJECT_FAILED", "RECOVERY_POINT_MODIFIED",
    ])
    error_message = "the vault must publish failed backup, copy and restore events (restore testing results included)."
  }
}
```

- [ ] **Step 2: Run, expect failure** (undeclared `notification_topic_arn`).
- [ ] **Step 3: Implement**

```hcl
variable "notification_topic_arn" {
  description = "SNS topic that receives failed backup, copy and restore (including restore-testing) events for this vault. Null (default) = none. The topic policy must allow backup.amazonaws.com to publish."
  type        = string
  default     = null
}

resource "aws_backup_vault_notifications" "this" {
  count             = var.notification_topic_arn != null ? 1 : 0
  backup_vault_name = aws_backup_vault.this.name
  sns_topic_arn     = var.notification_topic_arn
  backup_vault_events = [
    "BACKUP_JOB_FAILED", "COPY_JOB_FAILED", "RESTORE_JOB_FAILED",
    "S3_BACKUP_OBJECT_FAILED", "S3_RESTORE_OBJECT_FAILED", "RECOVERY_POINT_MODIFIED",
  ]
}
```

Expose `notification_topic_arn` on the backup stage (`copy_vault_notification_topic_arn`, default null) and pass it to `module.copy_vault`.

- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit** `feat(aws-backup): vault notifications for failed backup, copy and restore jobs (CMP-1)`

---

## Task 4: CMP-1d. Make the backup rows true

**Files:**
- Modify: `docs/compliance/control-matrix.md` rows BCK-01, BCK-02, BCK-03 and the "Technical gaps" row "AWS backups are single-region"
- Modify: `docs/architecture/landing-zone-conformance.md` (the AWS Backup sentence in "What each cloud already gets right" and the A5 gap row)
- Modify: `docs/runbooks/production-hardening.md` (add the backup step)

- [ ] **Step 1: Replace the matrix rows with this exact text**

| ID | Control | Cloud | Implementation (path · flag) | Default | Status | SOC 2 | ISO | NIST | CIS |
|:---|:--------|:------|:-----------------------------|:--------|:-------|:------|:----|:-----|:----|
| BCK-01 | Locked central copy. Every member recovery point is copied to `org-backup-copy-vault` in the delegated backup account: CMK-encrypted, **Compliance-mode Vault Lock**, copy-in allowed only from the organization (`aws:PrincipalOrgID`). Org-wide cross-account backup is on. Recovery points in the copy vault cannot be deleted before `min_retention_days`, even by root. The original `org-backup-vault` in the backup account receives nothing and is kept only because a locked vault cannot be removed. | AWS | `modules/aws/stages/backup` (`module.copy_vault`, `aws_backup_global_settings`) → `modules/aws/backup/backup-vault` · `compliance.backup.copy_to_central_vault`, `min_retention_days` (7), `changeable_for_days` (3) | **Off** (`compliance.backup.copy_to_central_vault: true`; the production scaffold sets it) | Mock; **PREVIEW** (copy jobs per resource type, A5) | A1.2 | A.8.13 | CP-9, CP-9(8), CP-6 | n/a |
| BCK-02 | Restore testing on real recovery points: a weekly restore-testing plan on the copy vault for EBS, EC2, RDS, Aurora, S3, DynamoDB and EFS, with failed restore, copy and backup jobs published to SNS. Without the copy vault, restore testing runs on the empty central vault and proves nothing. | AWS | `modules/aws/backup/backup-vault` · `restore_testing_resource_types`, `restore_testing_schedule`, `notification_topic_arn` | On only with BCK-01 | Mock; **PREVIEW** (RDS and Aurora restore metadata) | A1.3 | A.8.13, A.5.30 | CP-4, CP-9(1) | n/a |
| BCK-03 | Org `BACKUP_POLICY` on the Workloads OU: daily, retention `retention_days` (365), selected by tag `backup = true` (Aurora clusters are tagged by default), written to the member vault (`<vault_name>-cmk` when BCK-01 is on) and copied to the central copy vault and, with `compliance.backup.dr_region`, to a member vault in a second region. | AWS | `modules/aws/stages/backup` → `modules/aws/backup/backup-org-policy` · `copy_actions`, `retention_days`; DR vault `modules/aws/stages/organization/backup_role.tf` · `member_backup_dr_region` | On when root applied (copy: Off) | Mock | A1.2 | A.8.13, A.8.14 | CP-9, CP-6 | n/a |

Technical-gaps row becomes: "AWS cross-account and cross-region backup copy is opt-in (BCK-01, BCK-03) and not yet proven against a real apply. EBS volumes on the `aws/ebs` key cannot be copied across accounts." Delete the claim "AWS Backup: WORM backups with restore testing" from the conformance doc and point at BCK-01 with its default.

- [ ] **Step 2: `make links`**, expect pass.
- [ ] **Step 3: Commit** `docs(compliance): backup rows state the default and the copy opt-in (CMP-1)`

---

## Task 5: CMP-2 (GCP) and the `compliance` config section

**Files:**
- (Schema, example YAML and negative fixture landed in Task 1 Step 0.)
- Modify: `envs/gcp/organization/config.tf`, `variables.tf`, `main.tf:39-99`
- Modify: `modules/gcp/stages/organization/variables.tf:546-562` (description fix, CMP-19)
- Modify: `scripts/check-consistency.sh` (retention floor canonical string)
- Test: `envs/gcp/organization/tests/config.tftest.hcl`, new `envs/gcp/organization/tests/variables_validation.tftest.hcl`, fixture `envs/gcp/organization/tests/fixtures/landing-zone.compliance.yaml`

Irreversibility: with `enable_audit_bucket_lock = true` the bucket's retention policy is locked; GCS lets a locked retention period be increased, never decreased. A lower `audit_log_retention_days` on a locked bucket fails at apply. The lifecycle `Delete` age changes in place.

- [ ] **Step 1: Failing tests**

`envs/gcp/organization/tests/config.tftest.hcl` (reuse the file's existing `override_data` blocks):

```hcl
run "compliance_retention_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
  }

  assert {
    condition     = local.audit_log_retention_days == 2190
    error_message = "compliance.audit_log_retention_days must reach the organization stage."
  }
}

run "explicit_retention_beats_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
    audit_log_retention_days = 2555
  }

  assert {
    condition     = local.audit_log_retention_days == 2555
    error_message = "the explicit variable must win over compliance.audit_log_retention_days."
  }
}

run "retention_default_unchanged" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  assert {
    condition     = local.audit_log_retention_days == 365
    error_message = "with no config the retention must stay 365 days."
  }
}
```

Fixture `landing-zone.compliance.yaml` = the root's existing minimal fixture plus:

```yaml
compliance:
  frameworks: [hipaa]
  audit_log_retention_days: 2190
```

New `variables_validation.tftest.hcl` (same mocks and `override_data` as `config.tftest.hcl`):

```hcl
run "retention_below_framework_floor_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
    audit_log_retention_days = 365
  }

  expect_failures = [var.audit_log_retention_days]
}

run "retention_zero_fails" {
  command = plan

  variables {
    landing_zone_config_path = ""
    audit_log_retention_days = 0
  }

  expect_failures = [var.audit_log_retention_days]
}
```

- [ ] **Step 2: Run, expect failure**

`make test TEST_DIRS=envs/gcp/organization TERRAFORM=$TF` fails with `Reference to undeclared input variable "audit_log_retention_days"` and `Unsupported attribute: local.audit_log_retention_days`.

- [ ] **Step 3: Implement**

`config.tf` `cfg`:

```hcl
    audit_log_retention_days = try(tonumber(local.lz.compliance.audit_log_retention_days), null)
    compliance_frameworks    = try([for f in local.lz.compliance.frameworks : tostring(f)], [])
```

`config.tf` locals (after `cfg`):

```hcl
  # Framework audit-retention floors in days (canonical copy; check-consistency.sh).
  retention_floor_days     = { pci_dss = 365, hipaa = 2190, fedramp_moderate = 913, soc2 = 0, iso27001 = 0, nist_800_53 = 0, dora = 0, nis2 = 0, gdpr = 0 }
  retention_floor          = max(0, [for f in local.cfg.compliance_frameworks : lookup(local.retention_floor_days, f, 0)]...)
  audit_log_retention_days = coalesce(var.audit_log_retention_days, local.cfg.audit_log_retention_days, 365)
```

`variables.tf`:

```hcl
variable "audit_log_retention_days" {
  description = "Days the org audit bucket keeps audit logs (lifecycle delete, and the locked retention period when gcp.enable_audit_bucket_lock is true). Null = compliance.audit_log_retention_days in config/landing-zone.yaml, else 365. Must be at least the floor of every compliance.frameworks entry: pci_dss 365 (PCI DSS v4.0.1 10.5.1: 12 months, latest 3 months immediately available), hipaa 2190 (45 CFR 164.316(b)(2), 6 years), fedramp_moderate 913 (OMB M-21-31: 12 months active plus 18 months cold). On a locked bucket the value can only go up."
  type        = number
  default     = null

  # Inline effective value (not local.audit_log_retention_days, which depends on
  # this variable and would form a cycle). local.retention_floor reads only cfg.
  validation {
    condition     = coalesce(var.audit_log_retention_days, local.cfg.audit_log_retention_days, 365) >= max(1, local.retention_floor)
    error_message = "audit_log_retention_days (or compliance.audit_log_retention_days) is below 1 or below the ${local.retention_floor}-day floor of compliance.frameworks (${join(", ", local.cfg.compliance_frameworks)})."
  }
}
```

`main.tf` in `module "organization"`: `audit_log_retention_days = local.audit_log_retention_days`.

Stage description (`modules/gcp/stages/organization/variables.tf:547-555`), replace the bullet list with:

```text
    Days to retain audit logs in Cloud Storage. Set it from your retention
    schedule (compliance.audit_log_retention_days):
      - PCI DSS v4.0.1 10.5.1: at least 12 months, the latest 3 months
        immediately available (this bucket is immediately available).
      - HIPAA: 6 years is the common reading of 45 CFR 164.316(b)(2).
      - FedRAMP Rev5 AU-11 / OMB M-21-31: 12 months active plus 18 months
        cold storage (913 days in total when kept in one bucket).
    Must be >= 1. On a locked bucket it can only be increased.
```

`scripts/check-consistency.sh` (after the region regex block):

```bash
echo "==> Audit-retention framework floors are identical in every root"
floors="$(grep -rhoE 'retention_floor_days *= *\{[^}]*\}' envs --include=config.tf | sed 's/  */ /g' | sort -u)"
[ "$(printf '%s\n' "$floors" | grep -c .)" -le 1 ] || { note "retention_floor_days drift: $floors"; fail=1; }
```

- [ ] **Step 4: Run, expect pass.** Then `make config-check` (expect the negative fixture rejected) and `make consistency`.
- [ ] **Step 5: Docs**
  - `UPGRADING.md` `### GCP`: "**`audit_log_retention_days` is now a root input (CMP-2).** It reads `compliance.audit_log_retention_days`; the default stays 365. A value below a listed framework's floor fails the plan. On a locked audit bucket a lower value fails at apply (GCS never shortens a locked retention period)."
  - Matrix LOG-02: Implementation column becomes `envs/gcp/organization` · `audit_log_retention_days` / `compliance.audit_log_retention_days` (365).
- [ ] **Step 6: Commit** `feat(gcp-organization): audit retention from config with framework floors (CMP-2, CMP-19)`

---

## Task 6: CMP-2 (AWS). Log-archive retention and Object Lock mode from config

**Files:**
- Modify: `modules/aws/stages/security/variables.tf:100-200` (aws object), `main.tf:184-196`
- Modify: `envs/aws/security/config.tf`, `variables.tf:72-110`
- Test: `modules/aws/stages/security/tests/wiring.tftest.hcl`, `envs/aws/security/tests/config.tftest.hcl`, `envs/aws/security/tests/variables_validation.tftest.hcl`

Irreversibility: the bucket's default Object Lock retention applies to new objects only. Objects already written in COMPLIANCE mode keep their retain-until date; it cannot be shortened by anyone. Raising `retention_days` is safe; lowering it only affects new objects and the lifecycle expiry. Switching `object_lock_mode` from COMPLIANCE to GOVERNANCE weakens the control for new objects; the stage validation refuses that when any framework is listed.

- [ ] **Step 1: Failing tests**

`modules/aws/stages/security/tests/wiring.tftest.hcl` (the log-archive module is nested; assert through a new stage output):

```hcl
run "log_archive_retention_wired" {
  command = plan

  variables {
    aws = {
      log_archive_bucket_name    = "acme-org-log-archive"
      log_archive_retention_days = 2190
    }
  }

  assert {
    condition     = output.log_archive_retention_days == 2190
    error_message = "aws.log_archive_retention_days must reach the log-archive bucket."
  }
}
```

(Merge into the file's existing `variables` shape for `var.aws`; the test only overrides the two keys shown.)

`envs/aws/security/tests/config.tftest.hcl`:

```hcl
run "compliance_retention_feeds_log_archive" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
  }

  assert {
    condition     = local.aws.log_archive_retention_days == 2190
    error_message = "compliance.audit_log_retention_days must feed aws.log_archive_retention_days."
  }
}
```

`envs/aws/security/tests/variables_validation.tftest.hcl`:

```hcl
run "log_archive_retention_below_floor_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
    aws_overrides            = { log_archive_retention_days = 365 }
  }

  expect_failures = [var.aws_overrides]
}
```

- [ ] **Step 2: Run, expect failure** (unknown attribute `log_archive_retention_days`).
- [ ] **Step 3: Implement**

Stage `aws` object additions:

```hcl
    # Days the log-archive bucket keeps objects (Object Lock default retention and
    # lifecycle expiry). New objects only: existing COMPLIANCE-mode objects keep
    # their retain-until date.
    log_archive_retention_days = optional(number, 365)
    # COMPLIANCE (default) or GOVERNANCE for new objects.
    log_archive_object_lock_mode = optional(string, "COMPLIANCE")
```

Stage validations: `var.aws.log_archive_retention_days >= 1`, `contains(["COMPLIANCE", "GOVERNANCE"], var.aws.log_archive_object_lock_mode)`. `main.tf` `module "log_archive_bucket"`: `retention_days = var.aws.log_archive_retention_days`, `object_lock_mode = var.aws.log_archive_object_lock_mode`. Output `log_archive_retention_days = var.aws.log_archive_retention_days`.

Root: `aws_overrides` gains `log_archive_retention_days = optional(number)` and `log_archive_object_lock_mode = optional(string)`; `cfg` reads `compliance.audit_log_retention_days` and `compliance.frameworks`; `lz_aws.log_archive_retention_days = local.cfg.audit_log_retention_days`; the same `retention_floor_days` local as Task 5; validation on `var.aws_overrides`:

```hcl
  validation {
    condition     = coalesce(try(var.aws_overrides.log_archive_retention_days, null), local.cfg.audit_log_retention_days, 365) >= local.retention_floor
    error_message = "The log-archive retention (aws_overrides.log_archive_retention_days, else compliance.audit_log_retention_days, else 365) is below the floor of compliance.frameworks."
  }

  validation {
    condition     = length(local.cfg.compliance_frameworks) == 0 || coalesce(try(var.aws_overrides.log_archive_object_lock_mode, null), "COMPLIANCE") == "COMPLIANCE"
    error_message = "With compliance.frameworks set, log_archive_object_lock_mode must stay COMPLIANCE."
  }
```

- [ ] **Step 4: Run, expect pass** (`make test TEST_DIRS="modules/aws/stages/security envs/aws/security" TERRAFORM=$TF`).
- [ ] **Step 5: Docs.** Matrix LOG-08: replace "(module defaults; not exposed at `envs/aws/security`)" with "`compliance.audit_log_retention_days` / `aws_overrides.log_archive_retention_days` (365), `log_archive_object_lock_mode` (COMPLIANCE)". `UPGRADING.md` `### AWS`: "**Log-archive retention from config (CMP-2).** Raising it changes the default retention for new objects only; objects already locked in COMPLIANCE mode keep their date and cannot be shortened."
- [ ] **Step 6: Commit** `feat(aws-security): log-archive retention and lock mode from config (CMP-2)`

---

## Task 7: CMP-3. Patch installation, not only a baseline

**Files:**
- Modify: `modules/aws/ops/systems-manager/main.tf`, `variables.tf:57-84`, `outputs.tf`
- Modify: `modules/aws/stages/workload/main.tf:225-240`, `modules/aws/stages/workload/variables.tf` (pass-through `enable_patch_install`, `patch_operating_systems`)
- Test: `modules/aws/ops/systems-manager/tests/plan_assertions.tftest.hcl`, `tests/variables_validation.tftest.hcl`

Existing-mechanism check: `grep -rn "AWS-RunPatchBaseline\|aws_ssm_maintenance_window" modules` is empty. A State Manager association with a cron schedule is the AWS-documented way to patch without a maintenance window, so no window is added.

- [ ] **Step 1: Failing tests** (replace the AL2 assertion in `plan_assertions.tftest.hcl`)

```hcl
run "patches_are_installed" {
  command = plan

  assert {
    condition     = toset(keys(aws_ssm_patch_baseline.this)) == toset(["AMAZON_LINUX_2023"])
    error_message = "the default baseline must target Amazon Linux 2023 (Amazon Linux 2 support ended 2026-06-30)."
  }

  assert {
    condition = (
      aws_ssm_association.patch_scan.name == "AWS-RunPatchBaseline" &&
      aws_ssm_association.patch_scan.parameters["Operation"] == "Scan" &&
      aws_ssm_association.patch_scan.schedule_expression == "rate(1 day)"
    )
    error_message = "a daily scan association must report patch compliance on every managed instance."
  }

  assert {
    condition = (
      aws_ssm_association.patch_install[0].name == "AWS-RunPatchBaseline" &&
      aws_ssm_association.patch_install[0].parameters["Operation"] == "Install" &&
      aws_ssm_association.patch_install[0].parameters["RebootOption"] == "RebootIfNeeded" &&
      aws_ssm_association.patch_install[0].schedule_expression == "cron(0 3 ? * SUN *)" &&
      aws_ssm_association.patch_install[0].max_concurrency == "10%" &&
      aws_ssm_association.patch_install[0].compliance_severity == "CRITICAL"
    )
    error_message = "a weekly install association must apply approved patches."
  }
}

run "install_can_be_disabled" {
  command = plan

  variables {
    enable_patch_install = false
  }

  assert {
    condition     = length(aws_ssm_association.patch_install) == 0 && aws_ssm_association.patch_scan.parameters["Operation"] == "Scan"
    error_message = "disabling install must keep the scan."
  }
}

run "several_operating_systems" {
  command = plan

  variables {
    patch_operating_systems = ["AMAZON_LINUX_2023", "UBUNTU"]
  }

  assert {
    condition     = toset(keys(aws_ssm_default_patch_baseline.this)) == toset(["AMAZON_LINUX_2023", "UBUNTU"])
    error_message = "every listed OS must get its own default baseline."
  }
}
```

`variables_validation.tftest.hcl`:

```hcl
run "rejects_unknown_reboot_option" {
  command = plan

  variables {
    patch_reboot_option = "Always"
  }

  expect_failures = [var.patch_reboot_option]
}
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

```hcl
variable "patch_operating_systems" {
  description = "Operating systems that get a patch baseline, each set as the account default for that OS. Amazon Linux 2 reached end of support on 2026-06-30: keep it here only while you still run it."
  type        = set(string)
  default     = ["AMAZON_LINUX_2023"]
  nullable    = false

  validation {
    condition = length(var.patch_operating_systems) > 0 && alltrue([for os in var.patch_operating_systems : contains([
      "AMAZON_LINUX_2023", "AMAZON_LINUX_2", "UBUNTU", "REDHAT_ENTERPRISE_LINUX", "WINDOWS", "SUSE", "DEBIAN", "ROCKY_LINUX", "ALMA_LINUX", "ORACLE_LINUX", "CENTOS", "MACOS",
    ], os)])
    error_message = "patch_operating_systems must be non-empty Patch Manager operating system names."
  }
}

variable "enable_patch_install" {
  description = "Install approved patches on every managed instance on patch_install_schedule (AWS-RunPatchBaseline Operation=Install). False keeps the daily scan only."
  type        = bool
  default     = true
  nullable    = false
}

variable "patch_install_schedule" {
  description = "Cron or rate expression for the install association."
  type        = string
  default     = "cron(0 3 ? * SUN *)"
}

variable "patch_reboot_option" {
  description = "RebootIfNeeded (default) or NoReboot. NoReboot leaves instances in a pending-reboot state that Patch Manager reports as non-compliant."
  type        = string
  default     = "RebootIfNeeded"

  validation {
    condition     = contains(["RebootIfNeeded", "NoReboot"], var.patch_reboot_option)
    error_message = "patch_reboot_option must be RebootIfNeeded or NoReboot."
  }
}
```

Keep `patch_operating_system` for one release with `deprecated = "Use patch_operating_systems."` and `default = null`; effective set: `local.patch_operating_systems = var.patch_operating_system != null ? toset([var.patch_operating_system]) : var.patch_operating_systems`.

`main.tf`:

```hcl
resource "aws_ssm_patch_baseline" "this" {
  for_each         = local.patch_operating_systems
  name             = "${var.patch_baseline_name}-${lower(replace(each.key, "_", "-"))}"
  operating_system = each.key
  # approval_rule unchanged
  tags = var.tags
}

resource "aws_ssm_default_patch_baseline" "this" {
  for_each         = aws_ssm_patch_baseline.this
  baseline_id      = each.value.id
  operating_system = each.value.operating_system
}

moved {
  from = aws_ssm_patch_baseline.this
  to   = aws_ssm_patch_baseline.this["AMAZON_LINUX_2"]
}

moved {
  from = aws_ssm_default_patch_baseline.this
  to   = aws_ssm_default_patch_baseline.this["AMAZON_LINUX_2"]
}

resource "aws_ssm_association" "patch_scan" {
  name                = "AWS-RunPatchBaseline"
  association_name    = "${var.patch_baseline_name}-scan"
  schedule_expression = "rate(1 day)"
  parameters          = { Operation = "Scan" }
  compliance_severity = "HIGH"

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }

  tags = var.tags
}

resource "aws_ssm_association" "patch_install" {
  count               = var.enable_patch_install ? 1 : 0
  name                = "AWS-RunPatchBaseline"
  association_name    = "${var.patch_baseline_name}-install"
  schedule_expression = var.patch_install_schedule
  parameters          = { Operation = "Install", RebootOption = var.patch_reboot_option }
  compliance_severity = "CRITICAL"
  max_concurrency     = "10%"
  max_errors          = "10%"

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }

  tags = var.tags
}
```

The baseline `name` gains an OS suffix, which forces replacement of the existing baseline; keep the old name for the AL2 key to avoid that: `name = each.key == "AMAZON_LINUX_2" ? var.patch_baseline_name : "${var.patch_baseline_name}-${...}"`.

- [ ] **Step 4: Run, expect pass** (`make test TEST_DIRS="modules/aws/ops/systems-manager modules/aws/stages/workload modules/aws/stages/security" TERRAFORM=$TF`).
- [ ] **Step 5: Docs.**
  - Matrix VUL-04 becomes: "OS patching: per-OS SSM patch baselines (Security and Bugfix, Critical and Important, after `patch_approve_after_days`), a daily `AWS-RunPatchBaseline` Scan association and a weekly Install association (`RebootIfNeeded`, 10% concurrency) on every managed instance. Instances must be SSM-managed (agent plus instance profile, or Default Host Management Configuration)." Default: **On**. NIST: SI-2, SI-2(2). Add PCI 6.3.3 in the crosswalk (Task 23).
  - `UPGRADING.md` `### AWS`: "**Patch Manager now installs patches (CMP-3).** A weekly Install association reboots instances when a patch needs it (Sunday 03:00 UTC). Set `enable_patch_install = false` to keep scan-only. The default baseline OS is now Amazon Linux 2023; an estate still on Amazon Linux 2 sets `patch_operating_systems = [\"AMAZON_LINUX_2\", \"AMAZON_LINUX_2023\"]`, otherwise the AL2 baseline is destroyed and AWS's predefined AL2 baseline takes over."
- [ ] **Step 6: Commit** `feat(aws-ssm): install patches on a schedule and default to Amazon Linux 2023 (CMP-3)`

---

## Task 8: CMP-4. GCP audit store: WORM and separation of duties for regulated estates

**Files:**
- Modify: `config/landing-zone.schema.json` (`gcp.logging_project_id`, `gcp.logging_project_number`, `gcp.audit_store_waived`)
- Modify: `envs/gcp/organization/config.tf`, `main.tf`
- Modify: `modules/gcp/governance/cloud-audit-logs/main.tf:85-100` (checkov skip text)
- Modify: `examples/presets/prod-gcp-organization.tfvars:35-40`, `SECURITY.md:52`
- Test: `envs/gcp/organization/tests/config.tftest.hcl`, `variables_validation.tftest.hcl`

Irreversibility: `enable_audit_bucket_lock` locks the retention policy permanently and puts a lien on the project; `logging_project_id` moves the audit CMEK keys, which cannot be deleted (`stages/organization/main.tf:105-107`). So neither is turned on by a default. The plan instead: (1) promotes both to config so they are visible; (2) fails the plan when any environment is `compliance_class: regulated` and either is missing, unless `gcp.audit_store_waived: true`; (3) warns (a `check`, never failing) in the production profile.

- [ ] **Step 1: Failing tests**

`variables_validation.tftest.hcl`:

```hcl
run "regulated_estate_needs_worm_and_sod" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated.yaml"
  }

  expect_failures = [terraform_data.regulated_audit_store_guard]
}

run "regulated_estate_with_waiver_plans" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated-waived.yaml"
  }

  assert {
    condition     = local.regulated_environment_keys == ["prod"]
    error_message = "the waiver must let a regulated estate plan without the lock."
  }
}
```

`config.tftest.hcl`:

```hcl
run "logging_project_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated-sod.yaml"
  }

  assert {
    condition     = local.gcp.logging_project_id == "acme-logging-prod" && local.gcp.logging_project_number == "222233334444" && local.gcp.enable_audit_bucket_lock == true
    error_message = "gcp.logging_project_id/number and gcp.enable_audit_bucket_lock must flow from config into the stage object."
  }
}
```

Fixtures: `landing-zone.regulated.yaml` (one env `prod` with `is_production: true`, `compliance_class: regulated`, no logging project, no lock), `landing-zone.regulated-waived.yaml` (same plus `gcp.audit_store_waived: true`), `landing-zone.regulated-sod.yaml` (same plus `gcp.logging_project_id: acme-logging-prod`, `gcp.logging_project_number: "222233334444"`, `gcp.enable_audit_bucket_lock: true`).

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

`config.tf` `cfg`: `logging_project_id`, `logging_project_number` (`tostring`), `audit_store_waived` (`tobool`), and in the `environments` normaliser `compliance_class = tostring(try(e.compliance_class, "standard"))`. `lz_gcp` gains `logging_project_id = local.cfg.logging_project_id` and `logging_project_number = local.cfg.logging_project_number`. Locals:

```hcl
  regulated_environment_keys = sort([for k, e in coalesce(local.environments, {}) : k if try(e.compliance_class, "standard") == "regulated"])
  audit_store_hardened       = local.gcp.logging_project_id != null && coalesce(local.gcp.enable_audit_bucket_lock, false)
```

The root's `var.environments` type gains `compliance_class = optional(string, "standard")` with a validation against `standard|regulated`.

`main.tf`:

```hcl
# CMP-4: a regulated estate keeps its audit store WORM-locked in a project the
# automation identity does not own. Both settings are irreversible, so they are
# never defaults: the plan fails until they are set or explicitly waived.
resource "terraform_data" "regulated_audit_store_guard" {
  input = local.regulated_environment_keys

  lifecycle {
    precondition {
      condition     = length(local.regulated_environment_keys) == 0 || local.audit_store_hardened || coalesce(local.cfg.audit_store_waived, false)
      error_message = "Regulated environments (${join(", ", local.regulated_environment_keys)}) need gcp.logging_project_id + gcp.logging_project_number (decide before the first apply: the audit keys cannot be moved) and gcp.enable_audit_bucket_lock: true (IRREVERSIBLE). Or set gcp.audit_store_waived: true and record why."
    }
  }
}

check "production_audit_store" {
  assert {
    condition     = local.profile != "production" || local.audit_store_hardened
    error_message = "Production profile: the audit bucket is not WORM-locked or shares the admin project. Auditors testing AU-9 / PCI 10.3.3 will flag this. See docs/runbooks/production-hardening.md."
  }
}
```

Checkov skip text (`cloud-audit-logs/main.tf:85-91`), replace item 1 with: "1. The sink stores nothing; this bucket IS the stored copy. Without the lock, an identity with storage.objects.delete or lifecycle rights on this bucket can remove audit history. The opt-in lock (enable_bucket_lock) and admin containment (IAM-12 deny policy on `containment/protected`) are the tamper controls."

Preset: uncomment nothing; replace the comment block with a pointer to `gcp.logging_project_id` / `gcp.enable_audit_bucket_lock` in `config/landing-zone.yaml` and the guard.

- [ ] **Step 4: Run, expect pass**, then `make config-check`.
- [ ] **Step 5: Docs.** Matrix LOG-03 Default: "Off; **required** for `compliance_class: regulated` (plan fails unless set or `gcp.audit_store_waived`); production profile warns." LOG-04 likewise. `SECURITY.md:52`: "Opt-in WORM retention: `gcp.enable_audit_bucket_lock` locks the audit bucket's retention policy (irreversible). Required for regulated environments." `UPGRADING.md` `### GCP`: "**Regulated environments require a hardened audit store (CMP-4).** Setting `compliance_class: regulated` on a GCP environment fails the `gcp-organization` plan until `gcp.logging_project_id`, `gcp.logging_project_number` and `gcp.enable_audit_bucket_lock: true` are set, or `gcp.audit_store_waived: true`. The lock is irreversible. Moving an existing estate to a logging project leaves the old audit keys behind (KMS keys cannot be deleted): plan it as a new audit store, keep the old bucket until its retention ends."
- [ ] **Step 6: Commit** `feat(gcp-organization): require WORM and a separate logging project for regulated estates (CMP-4)`

---

## Task 9: CMP-5. TLS 1.2 floor on GCP public ingress and Google APIs

**Files:**
- Modify: `modules/gcp/network/app-ingress/main.tf:64-72`, `variables.tf:62-66`, `outputs.tf`
- Modify: `modules/gcp/stages/organization/main.tf:365-434`, `variables.tf` (gcp object `restrict_tls_versions`)
- Modify: `envs/gcp/organization/main.tf:55-64`, `variables.tf` (`gcp_overrides.restrict_tls_versions`)
- Test: `modules/gcp/network/app-ingress/tests/plan_assertions.tftest.hcl`, `variables_validation.tftest.hcl`; `modules/gcp/stages/organization/tests/plan_assertions.tftest.hcl`

Existing mechanism: `app-ingress` already accepts `ssl_policy_id`. The task creates the policy when none is passed; callers that pass one are unchanged.

- [ ] **Step 1: Failing tests** (app-ingress; reuse its `variables` block)

```hcl
run "tls_floor_by_default" {
  command = plan

  assert {
    condition = (
      google_compute_ssl_policy.this[0].min_tls_version == "TLS_1_2" &&
      google_compute_ssl_policy.this[0].profile == "MODERN"
    )
    error_message = "public ingress must get a MODERN, TLS 1.2 minimum SSL policy when none is passed."
  }
}

run "external_ssl_policy_wins" {
  command = plan

  variables {
    ssl_policy_id = "projects/p/global/sslPolicies/restricted-13"
  }

  assert {
    condition     = length(google_compute_ssl_policy.this) == 0 && google_compute_target_https_proxy.this.ssl_policy == "projects/p/global/sslPolicies/restricted-13"
    error_message = "a caller-supplied SSL policy must be used as is."
  }
}
```

`variables_validation.tftest.hcl`:

```hcl
run "rejects_tls_1_0" {
  command = plan

  variables {
    min_tls_version = "TLS_1_0"
  }

  expect_failures = [var.min_tls_version]
}
```

Org stage `plan_assertions.tftest.hcl` (stage-level local, not nested):

```hcl
run "restrict_tls_versions_policy" {
  command = plan

  variables {
    # The file-level gcp object (plan_assertions.tftest.hcl:26-35) plus the key under test.
    gcp = {
      admin_email                           = "admin@acme.io"
      break_glass_user                      = "break-glass@acme.io"
      organization_admin_groups             = ["org-admins@acme.io"]
      billing_admin_groups                  = ["billing-admins@acme.io"]
      allowed_regions                       = ["europe-west1"]
      strict_folder_policy_environment_keys = ["prod"]
      budget_currency                       = "USD"
      alert_notification_emails             = ["secops@acme.io"]
      restrict_tls_versions                 = true
    }
  }

  assert {
    condition = anytrue([
      for p in local.effective_list_policies :
      p.constraint == "gcp.restrictTLSVersion" && toset(p.denied_values) == toset(["TLS_VERSION_1", "TLS_VERSION_1_1"])
    ])
    error_message = "restrict_tls_versions must deny TLS 1.0 and 1.1 to Google APIs org-wide."
  }
}
```


- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

app-ingress:

```hcl
variable "min_tls_version" {
  description = "Minimum TLS version of the SSL policy this module creates when ssl_policy_id is null."
  type        = string
  default     = "TLS_1_2"

  validation {
    condition     = contains(["TLS_1_2", "TLS_1_3"], var.min_tls_version)
    error_message = "min_tls_version must be TLS_1_2 or TLS_1_3."
  }
}

variable "ssl_policy_profile" {
  description = "Profile of the created SSL policy: MODERN (default) or RESTRICTED (required for TLS_1_3)."
  type        = string
  default     = "MODERN"

  validation {
    condition     = contains(["MODERN", "RESTRICTED"], var.ssl_policy_profile) && (var.min_tls_version != "TLS_1_3" || var.ssl_policy_profile == "RESTRICTED")
    error_message = "ssl_policy_profile must be MODERN or RESTRICTED, and RESTRICTED when min_tls_version is TLS_1_3."
  }
}

resource "google_compute_ssl_policy" "this" {
  count           = var.ssl_policy_id == null ? 1 : 0
  project         = var.project_id
  name            = "${var.name}-tls"
  profile         = var.ssl_policy_profile
  min_tls_version = var.min_tls_version
}
```

Proxy: `ssl_policy = coalesce(var.ssl_policy_id, try(google_compute_ssl_policy.this[0].id, null))`. Update the `ssl_policy_id` description ("Null creates a MODERN TLS 1.2 policy").

Org stage: gcp object `restrict_tls_versions = optional(bool, false)`; in `default_list_policies` concat:

```hcl
    var.gcp.restrict_tls_versions ? [{
      constraint     = "gcp.restrictTLSVersion"
      allowed_values = null
      denied_values  = ["TLS_VERSION_1", "TLS_VERSION_1_1"]
      allow_all      = null
      deny_all       = null
    }] : [],
```

Root: `gcp = merge(local.gcp, { ..., restrict_tls_versions = coalesce(try(local.gcp.restrict_tls_versions, null), local.profile == "production") })`.

- [ ] **Step 4: Run, expect pass** (`make test TEST_DIRS="modules/gcp/network/app-ingress modules/gcp/stages/organization modules/gcp/stages/environment envs/gcp/organization" TERRAFORM=$TF`).
- [ ] **Step 5: Docs.** Matrix DP-04 adds "GCP: public ingress SSL policy MODERN, TLS 1.2 minimum (`app-ingress` · `min_tls_version`); `gcp.restrictTLSVersion` denies TLS 1.0/1.1 to Google APIs (production profile)". `UPGRADING.md` `### GCP`: "**TLS 1.2 minimum on public ingress (CMP-5).** Each `public_ingress` load balancer gets a MODERN SSL policy; clients that only speak TLS 1.0 or 1.1 can no longer connect. The production profile also sets `gcp.restrictTLSVersion`; opt out with `gcp_overrides.restrict_tls_versions = false`."
- [ ] **Step 6: Commit** `feat(gcp): TLS 1.2 minimum on public ingress and Google APIs (CMP-5)`

---

## Task 10: CMP-6. No placeholder security mailbox

**Files:**
- Modify: `envs/aws/security/config.tf:76-79`, `main.tf`
- Modify: `envs/aws/security/tests/contract.tftest.hcl:229-237` and every run in `envs/aws/security/tests/*.tftest.hcl` that relies on the placeholder (add a file-level `variables { aws_overrides = { notification_subscribers = { secops = { protocol = "email", endpoint = "secops@acme.test" } } } }` where needed)
- Test: `envs/aws/security/tests/variables_validation.tftest.hcl`

Existing mechanism: `notifications.emails` already feeds the subscriber map (`config.tf:55-58`). Only the fallback changes.

- [ ] **Step 1: Failing tests**

```hcl
run "production_without_security_contact_fails" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  expect_failures = [terraform_data.security_contact_guard]
}

run "placeholder_domain_rejected_in_production" {
  command = plan

  variables {
    landing_zone_config_path = ""
    aws_overrides = {
      notification_subscribers = { secops = { protocol = "email", endpoint = "secops@example.com" } }
    }
  }

  expect_failures = [terraform_data.security_contact_guard]
}

run "starter_profile_only_warns" {
  command = plan

  variables {
    landing_zone_config_path = ""
    profile                  = "starter"
  }

  assert {
    condition     = length(local.notification_subscribers) == 0
    error_message = "starter with no contact must plan with no subscriber (a check block warns)."
  }
}
```

Replace `contract.tftest.hcl` run `no_section_is_noop` assertion with `length(local.notification_subscribers) == 0`.

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

`config.tf`: fallback becomes `tomap({})`. `main.tf`:

```hcl
locals {
  placeholder_contact = anytrue([for s in values(local.notification_subscribers) : can(regex("@(example\\.(com|org|net)|.*\\.invalid)$", s.endpoint))])
}

# CMP-6: production security alerts must reach a real, staffed address.
resource "terraform_data" "security_contact_guard" {
  input = keys(local.notification_subscribers)

  lifecycle {
    precondition {
      condition     = local.profile != "production" || (length(local.notification_subscribers) > 0 && !local.placeholder_contact)
      error_message = "Production security notifications have no real subscriber. Set notifications.emails in config/landing-zone.yaml (or aws_overrides.notification_subscribers). Example and .invalid domains are rejected."
    }
  }
}

check "security_contact_set" {
  assert {
    condition     = length(local.notification_subscribers) > 0
    error_message = "No security notification subscriber is set: GuardDuty, Security Hub and break-glass alerts go nowhere."
  }
}
```

Confirm `module "security"` accepts an empty `notification_subscribers` map (`grep -n notification_subscribers modules/aws/security/security-notifications/variables.tf`); if it requires non-empty, relax that validation to allow `{}`.

- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Docs.** `UPGRADING.md` `### AWS`: "**No placeholder SecOps subscriber (CMP-6).** `aws-security` no longer subscribes `secops@example.com`. A production-profile plan fails until `notifications.emails` (or `aws_overrides.notification_subscribers`) names a real address. The old subscription is destroyed (it never delivered)." Matrix LOG-10 Default: "On; needs `notifications.emails` (production plan fails without it)".
- [ ] **Step 6: Commit** `fix(aws-security): require a real security contact in production (CMP-6)`

---

## Task 11: CMP-7. An opt-in `regulated` environment class

**Files:**
- Modify: `config/landing-zone.schema.json` (per-env `compliance_class`, shared contract)
- Create: `examples/presets/regulated-gcp-workload.yaml`
- Modify: `envs/gcp/workload/config.tf:180-196`, `main.tf:298-307`, `variables.tf:265-286`
- Modify: `envs/aws/network/config.tf:49-52,83`, `main.tf:70-80`
- Modify: `modules/aws/network/vpc-endpoints/main.tf:25-42`, `variables.tf`; `modules/aws/stages/network-hub/main.tf:430-440`, `variables.tf`
- Test: `envs/gcp/workload/tests/config.tftest.hcl` (or the file holding preset tests: `grep -ln preset envs/gcp/workload/tests`), `envs/aws/network/tests/config.tftest.hcl`, `modules/aws/network/vpc-endpoints/tests/plan_assertions.tftest.hcl`

What `regulated` turns on, per cloud (no other environment changes):

| Control | GCP (`envs/gcp/workload`) | AWS |
|:--|:--|:--|
| Exfiltration perimeter | VPC-SC enforced: the existing `check "vpc_sc_enforced_in_prod"` becomes a precondition for regulated envs | Endpoint policy adds `aws:ResourceOrgID` (D8) |
| Egress inspection | n/a (Cloud NAT plus firewall policy) | `enforce_egress_allowlist` forced on for any regulated workload env, waiver refused |
| Flow logs | sampling 1.0, `INTERVAL_5_SEC`, retention 365 days | already `ALL` to the log archive (LOG-13) |
| Edge | Cloud Armor and OWASP rules on (existing preset keys) | n/a |
| Data | Cloud SQL CMEK required (Task 17), Backup vault on (Task 12), `data-classification` tag `restricted` (Task 15) | Aurora CMK already required |

Dependency: an enforced perimeter blocks the TFC service accounts unless `vpc_sc_ingress_identities` lists them (ARC-13, owned by another workstream). The regulated guard's message names that input.

- [ ] **Step 1: Failing tests**

GCP:

```hcl
run "regulated_env_turns_on_strict_preset" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated.yaml"
    environment              = "prod"
    vpc_sc_enable_dry_run    = false
  }

  assert {
    condition = (
      local.compliance_class == "regulated" &&
      local.enable_cloud_armor == true &&
      local.enable_owasp_rules == true &&
      local.flow_log_sampling == 1.0 &&
      local.flow_logs_retention_days == 365
    )
    error_message = "compliance_class: regulated must apply the regulated preset and full flow logs."
  }
}

run "regulated_env_rejects_dry_run_perimeter" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated.yaml"
    environment              = "prod"
  }

  expect_failures = [terraform_data.regulated_perimeter_guard]
}

run "standard_env_unchanged" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated.yaml"
    environment              = "dev"
  }

  assert {
    condition     = local.compliance_class == "standard" && local.flow_log_sampling == 0.1 && local.vpc_sc_enable_dry_run == true
    error_message = "a standard env in the same estate must keep today's defaults."
  }
}
```

(Reuse the root test file's existing `override_data` for the projects contract; the fixture defines `dev` and `prod`, with `prod.compliance_class: regulated`.)

AWS network:

```hcl
run "regulated_workload_forces_egress_gate" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated.yaml"
  }

  assert {
    condition     = local.enforce_egress_allowlist == true && local.endpoint_policy_mode == "org_principals_and_resources"
    error_message = "a regulated AWS workload env must force the egress gate and the resource-org endpoint policy, even on the starter profile."
  }
}

run "regulated_refuses_waiver" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.regulated-waived.yaml"
  }

  expect_failures = [var.egress_alert_only_waived]
}
```

(`landing-zone.regulated.yaml` here uses `org.profile: starter` and one `aws.workload_environments.pci` with `compliance_class: regulated`, to prove the class, not the profile, drives the gate.)

vpc-endpoints:

```hcl
run "resource_org_condition" {
  command = plan

  variables {
    endpoint_policy_mode = "org_principals_and_resources"
  }

  assert {
    condition     = jsondecode(aws_vpc_endpoint.interface["ssm"].policy).Statement[0].Condition.StringEquals["aws:ResourceOrgID"] == var.org_id
    error_message = "the regulated endpoint policy must also require org-owned resources."
  }
}
```

(Use a service from the module test's existing `interface_services` value in place of `ssm` if different.)

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

`examples/presets/regulated-gcp-workload.yaml`:

```yaml
# Regulated environment class (compliance_class: regulated). Applied by
# envs/gcp/workload for that environment only. Precedence: explicit variable >
# preset > config file > default.
root: envs/gcp/workload
values:
  vpc_sc_enable_dry_run: false
  enable_cloud_armor: true
  enable_owasp_rules: true
  log_config_flow_sampling: 1.0
  vpc_flow_logs_retention_days: 365
```

`envs/gcp/workload/config.tf`: `compliance_class = try(tostring(local.lz.gcp.environments[var.environment].compliance_class), "standard")`; `preset_names` appends `"regulated-gcp-workload"` when regulated; `preset_supported_keys` adds `log_config_flow_sampling`, `vpc_flow_logs_retention_days`; change those two variables to `default = null` and read `local.flow_log_sampling = var.log_config_flow_sampling != null ? var.log_config_flow_sampling : tonumber(lookup(local.preset, "log_config_flow_sampling", 0.1))` and `local.flow_logs_retention_days` likewise (30). Pass the locals at `main.tf:213,215`.

`envs/gcp/workload/main.tf` (next to the existing check):

```hcl
resource "terraform_data" "regulated_perimeter_guard" {
  input = local.compliance_class

  lifecycle {
    precondition {
      condition     = local.compliance_class != "regulated" || (local.vpc_sc_access_policy != null && !local.vpc_sc_enable_dry_run)
      error_message = "Environment '${var.environment}' is compliance_class: regulated, so its VPC-SC perimeter must be enforced (vpc_sc_enable_dry_run = false) with a scoped access policy. List the TFC apply identities in vpc_sc_ingress_identities first, or the enforced perimeter blocks the pipeline."
    }
  }
}
```

`modules/aws/network/vpc-endpoints`:

```hcl
variable "endpoint_policy_mode" {
  description = "Default endpoint policy when endpoint_policy_json is null. org_principals (default): callers must be in the organization. org_principals_and_resources: the resource must also belong to the organization (aws:ResourceOrgID), except the services in resource_org_exempt_services. Sandbox-prove it before use: AWS-owned resources (for example Amazon Linux repository buckets) are not in your organization."
  type        = string
  default     = "org_principals"

  validation {
    condition     = contains(["org_principals", "org_principals_and_resources"], var.endpoint_policy_mode)
    error_message = "endpoint_policy_mode must be org_principals or org_principals_and_resources."
  }
}

variable "resource_org_exempt_services" {
  description = "Interface services that keep the principal-only policy in org_principals_and_resources mode (their resources are AWS-owned)."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "ssm", "ssmmessages", "ec2messages", "logs", "monitoring", "sts"]
}
```

Policy expression:

```hcl
  policy = var.endpoint_policy_json != null ? var.endpoint_policy_json : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "*"
      Resource  = "*"
      Condition = {
        StringEquals = merge(
          { "aws:PrincipalOrgID" = var.org_id },
          var.endpoint_policy_mode == "org_principals_and_resources" && !contains(var.resource_org_exempt_services, each.value) ? { "aws:ResourceOrgID" = var.org_id } : {},
        )
      }
    }]
  })
```

(If the assertion in Step 1 targets an exempt service, pick a non-exempt one such as `kms` or `secretsmanager`.) Network-hub stage passes `endpoint_policy_mode` through.

`envs/aws/network/config.tf`: `workload_regulated = try([for k, e in local.lz.aws.workload_environments : k if try(tostring(e.compliance_class), "standard") == "regulated"], [])`; `enforce_egress_allowlist = coalesce(var.enforce_egress_allowlist, length(local.cfg.workload_regulated) > 0 || (local.profile == "production" && length(local.cfg.workload_production) > 0))`; `endpoint_policy_mode = length(local.cfg.workload_regulated) > 0 ? "org_principals_and_resources" : "org_principals"`. Validation on `var.egress_alert_only_waived`: `!(coalesce(var.egress_alert_only_waived, local.cfg.egress_alert_only_waived, false) && length(local.cfg.workload_regulated) > 0)`.

- [ ] **Step 4: Run, expect pass** (`make test TEST_DIRS="envs/gcp/workload envs/aws/network modules/aws/network/vpc-endpoints modules/aws/stages/network-hub" TERRAFORM=$TF`), `make config-check`.
- [ ] **Step 5: Docs.**
  - Create `docs/architecture/regulated-environments.md` with the table above, the fixture YAML, the ARC-13 dependency, and "What regulated does not give you: cardholder-data segmentation inside an environment, FIPS endpoints, sovereign partitions".
  - Matrix: new row **NET-11 Regulated environment class** (both clouds; Default **Off**, per environment; NIST SC-7, SC-7(5), AC-4, AU-12; PCI 1.3, 1.4, 10.2; HIPAA 164.312(e)(1)).
  - Matrix NET-05: "Default action `aws:alert_established`, but the plan fails (`enforce_egress_allowlist`) when `org.profile = production` and an AWS workload env is production, or any env is regulated."
  - `UPGRADING.md` `### All clouds`: "**`compliance_class: regulated` (CMP-7, opt-in).** Marks an environment as holding regulated data. On GCP it enforces VPC-SC (plan fails on dry-run), turns on Cloud Armor/OWASP, full flow-log sampling and 365-day flow-log retention. On AWS it forces the egress gate and refuses the waiver, and adds `aws:ResourceOrgID` to the hub endpoint policy. Full sampling raises Cloud Logging cost."
- [ ] **Step 6: Commit** `feat: opt-in regulated environment class on both clouds (CMP-7)`

---

## Task 12: CMP-8. GCP backups: stay in region, and a Backup and DR vault

**Files:**
- Modify: `modules/gcp/data/cloud-sql/main.tf:129-130`, `variables.tf:115-124`
- Create: `modules/gcp/backup/backup-vault/{main.tf,variables.tf,outputs.tf,versions.tf,README.md,tests/plan_assertions.tftest.hcl,tests/variables_validation.tftest.hcl,examples/basic/main.tf}`
- Modify: `modules/gcp/stages/environment/main.tf`, `variables.tf` (wire the vault for regulated envs)
- Modify: `envs/gcp/workload/main.tf`, `config.tf` (`enable_backup_vault` derived from `compliance_class`)
- Modify: `modules/gcp/stages/bootstrap/variables.tf:221-243` (workload apply folder roles gain `roles/backupdr.admin`), `CLAUDE.md` and `README.md` module counts (`make count-check`)
- Test: cloud-sql `plan_assertions.tftest.hcl`; the new module's two suites; `modules/gcp/stages/environment/tests/plan_assertions.tftest.hcl`

Lock-out check: the workload apply SA has only its folder roles (IAM-02); without `roles/backupdr.admin` (vault and plan) and `roles/backupdr.computeEngineOperator` the apply fails. The bootstrap grants them per env folder, so this needs a `gcp-bootstrap` apply first; the guardrails deny policy does not cover `backupdr.*` (`grep -rn backupdr modules/gcp/stages/guardrails` is empty).

Irreversibility: `backup_minimum_enforced_retention_duration` can be raised but not lowered; setting `effective_time` locks it permanently. The module never sets `effective_time` (documented as the owner's choice).

- [ ] **Step 1: Failing tests**

cloud-sql:

```hcl
run "backups_stay_in_instance_region" {
  command = plan

  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].location == "europe-west1"
    error_message = "with no backup_location, backups must stay in the instance region (gcp.resourceLocations), not Cloud SQL's multi-region default."
  }
}

run "explicit_backup_location_kept" {
  command = plan

  variables {
    backup_location = "eu"
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].location == "eu"
    error_message = "an explicit backup_location must win."
  }
}
```

New module `plan_assertions.tftest.hcl`:

```hcl
mock_provider "google" {}

variables {
  project_id              = "acme-prod-host"
  location                = "europe-west2"
  vault_id                = "prod-vault"
  enforced_retention_days = 35
  cloud_sql_instances     = { orders = "projects/acme-prod-svc/instances/orders-db" }
}

run "vault_and_plan" {
  command = plan

  assert {
    condition = (
      google_backup_dr_backup_vault.this.backup_minimum_enforced_retention_duration == "3024000s" &&
      google_backup_dr_backup_vault.this.access_restriction == "WITHIN_ORGANIZATION"
    )
    error_message = "the vault must enforce 35 days of retention and stay inside the organization."
  }

  assert {
    condition = (
      google_backup_dr_backup_plan.cloud_sql[0].resource_type == "sqladmin.googleapis.com/Instance" &&
      google_backup_dr_backup_plan.cloud_sql[0].backup_rules[0].backup_retention_days == 35 &&
      google_backup_dr_backup_plan.cloud_sql[0].backup_rules[0].standard_schedule[0].recurrence_type == "DAILY"
    )
    error_message = "Cloud SQL must get a daily plan at the enforced retention."
  }

  assert {
    condition     = google_backup_dr_backup_plan_association.cloud_sql["orders"].resource == "projects/acme-prod-svc/instances/orders-db"
    error_message = "every listed Cloud SQL instance must be associated with the plan."
  }

  assert {
    condition     = google_backup_dr_backup_vault.this.effective_time == null
    error_message = "the module must never lock the enforced retention on its own."
  }
}
```

`variables_validation.tftest.hcl`:

```hcl
mock_provider "google" {}

variables {
  project_id = "acme-prod-host"
  location   = "europe-west2"
  vault_id   = "prod-vault"
}

run "rejects_short_retention" {
  command = plan

  variables {
    enforced_retention_days = 0
  }

  expect_failures = [var.enforced_retention_days]
}

run "rejects_bad_instance_name" {
  command = plan

  variables {
    cloud_sql_instances = { bad = "orders-db" }
  }

  expect_failures = [var.cloud_sql_instances]
}
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

cloud-sql `main.tf:129-130`:

```hcl
      # Null = the instance region, so backups obey gcp.resourceLocations.
      # Set a multi-region (eu, us, asia) explicitly if the residency policy allows it.
      location = coalesce(var.backup_location, var.region)
```

New module `main.tf`:

```hcl
# Backup and DR vault (GCP twin of the AWS locked copy vault). Backups in the
# vault are immutable for enforced_retention_days; the vault refuses access from
# outside the organization. Locking the enforced retention (effective_time) is
# irreversible and left to the owner.
resource "google_backup_dr_backup_vault" "this" {
  project                                    = var.project_id
  location                                   = var.location
  backup_vault_id                            = var.vault_id
  description                                = "Landing-zone backup vault (enforced retention ${var.enforced_retention_days} days)."
  backup_minimum_enforced_retention_duration = "${var.enforced_retention_days * 86400}s"
  access_restriction                         = "WITHIN_ORGANIZATION"
  labels                                     = var.labels
}

resource "google_backup_dr_backup_plan" "cloud_sql" {
  count          = length(var.cloud_sql_instances) > 0 ? 1 : 0
  project        = var.project_id
  location       = var.location
  backup_plan_id = "${var.vault_id}-cloudsql"
  resource_type  = "sqladmin.googleapis.com/Instance"
  backup_vault   = google_backup_dr_backup_vault.this.id

  backup_rules {
    rule_id               = "daily"
    backup_retention_days = var.enforced_retention_days

    standard_schedule {
      recurrence_type  = "DAILY"
      hourly_frequency = null
      time_zone        = "UTC"

      backup_window {
        start_hour_of_day = 2
        end_hour_of_day   = 6
      }
    }
  }
}

resource "google_backup_dr_backup_plan_association" "cloud_sql" {
  for_each                   = var.cloud_sql_instances
  project                    = var.project_id
  location                   = var.location
  backup_plan_association_id = "${var.vault_id}-${each.key}"
  resource                   = each.value
  resource_type              = "sqladmin.googleapis.com/Instance"
  backup_plan                = google_backup_dr_backup_plan.cloud_sql[0].name
}
```

Variables: `project_id`, `location` (region regex), `vault_id` (`^[a-z][a-z0-9-]{0,62}$`), `enforced_retention_days` (number, default 35, `>= 1`), `cloud_sql_instances` (map(string), default `{}`, validation `^projects/[a-z][a-z0-9-]+/instances/[a-z][a-z0-9-]+$`), `labels`. Outputs: `vault_id`, `vault_name`, `service_account` (the vault's service agent, to which the caller grants `roles/cloudsql.viewer` on the source projects as the Backup and DR docs require; verify the exact role against the Backup and DR docs during the sandbox run). `versions.tf`: `google ~> 8.0`, Terraform `>= 1.17, < 2.0`.

Environment stage: `enable_backup_vault` (bool, false) creates `module "backup_vault"` in `var.host_project.project_id` / `var.host_project.region`, with `cloud_sql_instances = { for k, db in module.app_services.databases : k => db.instance_id }` (check the app-services output name; add an `instance_id` output if missing). `envs/gcp/workload`: `enable_backup_vault = local.compliance_class == "regulated"` (and a root variable override, default null).

- [ ] **Step 4: Run, expect pass** (`make test TEST_DIRS="modules/gcp/data/cloud-sql modules/gcp/backup/backup-vault modules/gcp/stages/environment envs/gcp/workload modules/gcp/stages/bootstrap" TERRAFORM=$TF`), then `make docs`, `make count-check` (update the module count in `README.md` and `CLAUDE.md`, 124 to 125).
- [ ] **Step 5: Docs.** Matrix BCK-04: add "backups default to the instance region (`backup_location`)". New row **BCK-07 GCP Backup and DR vault**: enforced retention, org-only access; Default **Off** (on for `compliance_class: regulated`); Status Mock, **PREVIEW**; SOC 2 A1.2; ISO A.8.13; NIST CP-9, CP-9(8). `docs/known-gaps.md`: new PREVIEW entry for the Backup and DR vault (service-agent grants, Cloud SQL association on a real apply). `UPGRADING.md` `### GCP`: "**Cloud SQL backups stay in the instance region (CMP-8).** `backup_location = null` now means the instance region, not Cloud SQL's nearest multi-region. Existing backups stay where they are; new ones land in the region. Set `backup_location = \"eu\"` (or `us`, `asia`) to keep multi-region backups. Regulated environments also get a Backup and DR vault; apply `gcp-bootstrap` first for the `roles/backupdr.*` folder grants."
- [ ] **Step 6: Commit** `feat(gcp-backup): region-pinned Cloud SQL backups and a Backup and DR vault for regulated envs (CMP-8)`

---

## Task 13: CMP-9. Regulatory breach-notification runbook

Docs only. No test; gate is `make links`.

**Files:**
- Create: `docs/runbooks/regulatory-notification.md`
- Modify: `docs/runbooks/incident-response.md` (link at the "Step 6" post-incident review heading and in "See also"), `docs/runbooks/aws-incident-response.md` (same), `docs/compliance/control-matrix.md` organizational row "Incident response" (link), `docs/README.md` or the runbook index if one lists runbooks (`grep -rn "incident-response.md" docs/*.md`)

- [ ] **Step 1: Write the runbook with this outline and content**

```markdown
# Runbook: Regulatory incident and breach notification

The clock starts when your organization becomes aware of the incident (GDPR,
NIS2, HIPAA) or classifies it as major (DORA), not when the investigation ends.
This runbook gives the deadlines, who decides, and where the landing zone's
evidence is. It is not legal advice: confirm each obligation with counsel and
your supervisory authority's current forms.

## 1. Roles (fill in before you need them)

| Role | Name | Backup | Decides |
|:--|:--|:--|:--|
| Incident commander | | | Severity, containment |
| Data protection officer | | | GDPR Art. 33/34 notification |
| Compliance officer (DORA / NIS2) | | | Major-incident classification, reports |
| HIPAA privacy officer | | | Breach risk assessment, notices |
| PCI contact | | | Acquirer and payment-brand notice |
| Legal counsel | | | Final wording, law enforcement |

The addresses in `compliance.breach_notification_contacts`
(`config/landing-zone.yaml`) are subscribed to the security alert topics
(AWS `security-notifications`, GCP control-plane alerts) so these people see the
first signal. Keep them current.

## 2. Deadlines at a glance

| Regime | Trigger | First notice | Then | Final | To whom |
|:--|:--|:--|:--|:--|:--|
| GDPR / UK GDPR Art. 33 | Personal-data breach, aware | Without undue delay, within **72 hours** where feasible | Phased information allowed (Art. 33(4)) | n/a | Lead supervisory authority |
| GDPR Art. 34 | High risk to individuals | Without undue delay | | | Data subjects |
| GDPR Art. 33(2) (you are a processor) | Aware | Without undue delay | | | The controller |
| DORA Art. 19 + RTS/ITS on reporting | Major ICT-related incident, classified | **4 hours** after classification, no later than **24 hours** after awareness | Intermediate report within **72 hours** of the initial notification | Within **1 month** of the latest intermediate report | Competent authority |
| NIS2 Art. 23 | Significant incident, aware | Early warning within **24 hours** | Incident notification within **72 hours** | Within **1 month** of the incident notification | CSIRT or competent authority |
| HIPAA Breach Notification Rule 164.404-408 | Breach of unsecured PHI, discovered | Individuals without unreasonable delay, no later than **60 days** | Media if more than 500 residents of a state; HHS at the same time if 500 or more | HHS annual log within 60 days of year end if fewer than 500 | Individuals, HHS, media |
| HIPAA 164.410 (you are a business associate) | Discovered | Without unreasonable delay, no later than **60 days** | | | The covered entity |
| PCI DSS v4.0.1 12.10.1 | Suspected or confirmed account-data compromise | Per your acquirer and payment-brand rules (plan must include them) | Forensic investigator (PFI) if required | | Acquirer, payment brands |
| US SEC Form 8-K Item 1.05 (listed US issuers) | Incident determined material | **4 business days** after the materiality determination | | | SEC |
| FedRAMP (out of scope for this repo) | Incident | Within **1 hour** of discovery | | | Agency, FedRAMP PMO, CISA |

## 3. Procedure

1. **T0: record awareness.** Open the incident ticket. Write the UTC time the
   organization became aware and who decided that. Every deadline above counts
   from this field (DORA: from classification).
2. **Classify (within 1 hour).** Answer, and record the answers:
   personal data involved (GDPR)? PHI (HIPAA)? cardholder data (PCI)? Are you a
   DORA financial entity, and does the incident meet the major-incident criteria
   (clients affected, duration, geographic spread, data losses, criticality,
   economic impact)? Are you an NIS2 essential or important entity, and is the
   incident significant?
3. **Preserve evidence before you change anything.** Run the evidence commands
   in section 4 and store the output in the incident folder.
4. **Start each clock that applies.** Put every deadline from section 2 in the
   ticket, with the owner from section 1.
5. **Draft the first notice.** Use the regulator's current form. Include what
   you know, what you do not know yet, and when you will update.
6. **Approve and send.** Counsel and the decider from section 1 approve. Record
   the time sent and the reference number.
7. **Update on schedule.** Intermediate and final reports as section 2 requires.
8. **Close.** Post-incident review (incident-response runbooks, Step 6), lessons,
   control changes, and a note in the risk register.

## 4. Evidence the landing zone gives you

| Question | AWS | GCP |
|:--|:--|:--|
| What did the attacker's identity do? | `aws cloudtrail lookup-events` or Athena on the log-archive bucket (LOG-07, LOG-08) | `gcloud logging read 'protoPayload.authenticationInfo.principalEmail="<id>"' --organization=<ORG_ID>` and the audit bucket (LOG-01, LOG-02) |
| Was data read? | S3 data events (LOG-07, `cloudtrail_s3_data_events`), Macie findings (DET-04) | Data Access logs (`DATA_READ`, LOG-01) |
| Network path | VPC flow logs in the log archive (LOG-13), Network Firewall alert logs (NET-05) | VPC flow logs in BigQuery (LOG-06) |
| Threat findings | GuardDuty and Security Hub exports (DET-01, DET-02) | SCC findings topic (DET-03) |
| Who changed the infrastructure? | HCP Terraform audit trail export (CHG-07) and run history | same |
| Are backups intact? | `aws backup list-recovery-points-by-backup-vault --backup-vault-name org-backup-copy-vault` (BCK-01) | `gcloud backup-dr backups list` (BCK-07) |
| Log integrity | `aws cloudtrail validate-logs` | Locked retention policy on the audit bucket (LOG-03) |

## 5. Templates

Short templates for: supervisory authority (GDPR Art. 33(3) content: nature,
categories and approximate numbers, DPO contact, likely consequences, measures);
DORA initial notification (fields of the ITS template); NIS2 early warning
(suspected unlawful or malicious cause, cross-border impact); HIPAA individual
notice (164.404(c) content). Keep the filled versions in the incident folder.

## 6. Test it

Run a tabletop at least yearly (DORA Art. 24-25, ISO A.5.24, SOC 2 CC7.4): one
scenario per regime that applies to you. Record the date and the gaps found.
```

- [ ] **Step 2: Wire `compliance.breach_notification_contacts`.** In `envs/aws/security/config.tf`, append the contacts to the subscriber map (`notify-dpo-<i>`), and in `envs/gcp/organization/config.tf` append them to `alert_notification_emails`. One test per root:

```hcl
run "breach_contacts_subscribed" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance.yaml"
  }

  assert {
    condition     = contains([for s in values(local.notification_subscribers) : s.endpoint], "dpo@acme.test")
    error_message = "compliance.breach_notification_contacts must receive security notifications."
  }
}
```

(GCP: `contains(local.gcp.alert_notification_emails, "dpo@acme.test")`. Add `breach_notification_contacts: [dpo@acme.test]` to both compliance fixtures.)

- [ ] **Step 3:** `make test TEST_DIRS="envs/aws/security envs/gcp/organization" TERRAFORM=$TF`, `make links`, `make config-check`.
- [ ] **Step 4: Commit** `docs(runbooks): regulatory incident and breach notification (CMP-9)`

---

## Task 14: ARC-8. Recovery objectives and the DR runbook

Docs plus one check. Code for cross-region copy is in Task 2 (`compliance.backup.dr_region`).

**Files:**
- Create: `docs/runbooks/disaster-recovery.md`
- Modify: `docs/compliance/control-matrix.md` organizational row "Business continuity and DR", `docs/known-gaps.md` (new entry "Single-region estate")

- [ ] **Step 1: Write the runbook** with these sections and this table as the core content:

```markdown
# Runbook: Disaster recovery and recovery objectives

## What this landing zone can recover, and how fast

These are design targets for a default single-region estate with the opt-ins
named in each row. They are not measured: no restore has run against a real
apply (docs/known-gaps.md). Replace them with your own measured values after
your first restore test.

| Asset | Mechanism | RPO (data loss) | RTO (time to restore) | Opt-in needed |
|:--|:--|:--|:--|:--|
| AWS workload data (EBS, RDS, Aurora, S3, DynamoDB, EFS) tagged `backup = true` | Org BACKUP_POLICY, daily at 05:00 UTC | up to 24 h | hours, per resource size | none |
| Same, after loss of the workload account | Copy in the locked central vault (BCK-01) | up to 24 h plus copy time | hours to a day (restore into a new account) | `compliance.backup.copy_to_central_vault` |
| Same, after loss of the home region | Copy in the member DR-region vault (BCK-03) | up to 24 h | a day or more (no warm standby network) | `compliance.backup.dr_region` |
| Aurora point in time | Native continuous backup (`backup_retention_period`) | about 5 minutes | under an hour in region | none |
| Cloud SQL point in time | PITR (`enable_point_in_time_recovery`) | minutes | under an hour in region | none |
| Cloud SQL after project loss | Backup and DR vault (BCK-07) | up to 24 h | hours | `compliance_class: regulated` |
| Terraform state | `state-backup.yml` to WORM buckets | up to 24 h | under an hour | repository variables |
| Landing-zone configuration | Git plus HCP Terraform | 0 | re-apply time per root | none |
| Audit logs | Locked GCS bucket / Object Lock S3 | 0 (streamed) | n/a (read in place) | LOG-03 for GCP |

## Not covered (decide and record)
- No warm standby region, no multi-region network or DNS failover.
- No Aurora Global Database; no Cloud SQL cross-region replica.
- SaaS (Supabase, Vercel): rely on the vendor; see docs/compliance/third-parties.md.

## Restore procedures
1. AWS resource from a member vault (console path and `aws backup start-restore-job`).
2. AWS resource from the central copy vault into a new account (share, copy back, restore).
3. AWS resource in the DR region.
4. Cloud SQL from PITR and from the Backup and DR vault.
5. Terraform state from the WORM bucket (link to state-backup.md).

## Test schedule
- Weekly automated restore testing (BCK-02) proves recoverability of single resources.
- A full DR exercise (account-loss scenario) at least yearly; record measured RPO/RTO here.
```

- [ ] **Step 2: Region check.** In `envs/aws/backup/main.tf`, a precondition on `terraform_data.backup_copy_guard`: `local.dr_region == null || (local.dr_region != local.aws_region && contains(local.aws_allowed_regions, local.dr_region))`, reading `aws.allowed_regions` from config (add to `cfg`). Test:

```hcl
run "dr_region_must_differ_and_be_allowed" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.compliance-bad-dr.yaml"
  }

  expect_failures = [terraform_data.backup_copy_guard]
}
```

(Fixture: `dr_region` equal to `org.regions.aws`.)
- [ ] **Step 3:** run the test, `make links`.
- [ ] **Step 4: Commit** `docs(runbooks): recovery objectives and DR procedure (ARC-8)`

---

## Task 15: CMP-10 and ARC-17. Required tags and data classification

**Files:**
- Modify: `modules/aws/governance/organization-policy/main.tf:269-272`, `variables.tf`; delete `policies/tag-policy.json` (replaced by `jsonencode`)
- Modify: `modules/aws/stages/organization/variables.tf`, `main.tf` (pass `tag_policy_required_resource_types`)
- Modify: `envs/aws/organization/config.tf`, `config/landing-zone.schema.json` (`aws.tagging.required_for`)
- Modify: `policies/opa/require_labels.rego`, `require_labels_test.rego`, `policies/opa/policies.hcl:93-96`
- Modify: every `envs/gcp/*/providers.tf` `gcp_default_labels` (add `cost-center`, `owner`)
- Modify: `modules/gcp/stages/projects` (bind `data-classification-<value>` to each host project), `envs/gcp/projects/outputs.tf:23-25`
- Test: `modules/aws/governance/organization-policy/tests/plan_assertions.tftest.hcl`, `policies/opa/require_labels_test.rego`, `envs/gcp/projects/tests/root.tftest.hcl`

Existing mechanisms reused: the root-attached tag policy (`stages/organization/main.tf:50`), the `require_labels` OPA policy, the `data-classification` GCP tag key (`stages/organization/main.tf:250-253`), `gcp/project` `tag_bindings` (`modules/gcp/project/variables.tf:174-182`). New platform feature used: AWS tag policies `report_required_tag_for` plus the provider's `tag_policy_compliance` setting (present in hashicorp/aws 6.72.0; checked with `terraform providers schema`). The provider setting is turned on per workspace with the existing `config/tfc-workspaces.yaml` env-var mechanism (`TF_AWS_TAG_POLICY_COMPLIANCE=error`), so no root code changes for it. The plan roles must be able to call the tag-policy API the provider uses; validate in the sandbox that `ReadOnlyAccess` covers it before setting `error`.

- [ ] **Step 1: Failing tests**

organization-policy:

```hcl
run "tag_policy_requires_keys" {
  command = plan

  variables {
    tag_policy_required_resource_types = ["ec2:instance", "s3:bucket", "rds:db"]
  }

  assert {
    condition = (
      jsondecode(aws_organizations_policy.policy["tag-policy"].content).tags.DataClassification.tag_key["@@assign"] == "DataClassification" &&
      toset(jsondecode(aws_organizations_policy.policy["tag-policy"].content).tags.DataClassification.tag_value["@@assign"]) == toset(["public", "internal", "confidential", "restricted"]) &&
      toset(jsondecode(aws_organizations_policy.policy["tag-policy"].content).tags.CostCenter.report_required_tag_for["@@assign"]) == toset(["ec2:instance", "s3:bucket", "rds:db"])
    )
    error_message = "the tag policy must define DataClassification values and report the required keys for the listed types."
  }
}

run "tag_policy_default_reports_nothing" {
  command = plan

  assert {
    condition     = !can(jsondecode(aws_organizations_policy.policy["tag-policy"].content).tags.CostCenter.report_required_tag_for)
    error_message = "with no resource types the tag policy must not require anything (unchanged behaviour)."
  }
}
```

(`aws_organizations_policy.policy` is keyed by policy name, `organization-policy/main.tf:291`.)

Rego (`require_labels_test.rego`, replace the "at least one" tests):

```rego
test_gcp_with_required_labels_passes if {
	count(p.deny) == 0 with input as one("google_storage_bucket", {"effective_labels": {"environment": "prod", "cost-center": "platform", "owner": "platform-team", "managed-by": "terraform"}}, {})
}

test_gcp_missing_cost_center_fails if {
	count(p.deny) == 1 with input as one("google_storage_bucket", {"effective_labels": {"environment": "prod", "owner": "platform-team"}}, {})
}

test_aws_with_required_tags_passes if {
	count(p.deny) == 0 with input as one("aws_s3_bucket", {"tags_all": {"Environment": "prod", "CostCenter": "platform", "Owner": "platform-team"}}, {})
}

test_aws_missing_owner_fails if {
	count(p.deny) == 1 with input as one("aws_kms_key", {"tags_all": {"Environment": "prod", "CostCenter": "platform"}}, {})
}

test_unknown_tags_still_pass if {
	count(p.deny) == 0 with input as one("aws_vpc", {}, {"tags_all": true})
}
```

GCP projects root (reuse the root test's mocks; fixture env `prod` with `data_classification: restricted`):

```hcl
run "data_classification_bound" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.classified.yaml"
  }

  assert {
    condition     = output.contract.environment_config["prod"].tag_value_ids.data_classification == "tagValues/900000000004"
    error_message = "each environment's host project must be bound to its data-classification tag value."
  }
}
```

(The organization contract override in that test needs `tag_values = { "environment-prod" = "...", "data-classification-restricted" = "tagValues/900000000004" }`.)

- [ ] **Step 2: Run, expect failure** (`make test TEST_DIRS="modules/aws/governance/organization-policy envs/gcp/projects" TERRAFORM=$TF`; `opa test policies/opa -v`).
- [ ] **Step 3: Implement**

Build the tag policy with `jsonencode` (repo rule 3), not a template file. In `organization-policy/main.tf`:

```hcl
locals {
  tag_policy_keys = {
    CostCenter         = null
    Environment        = null
    Owner              = null
    DataClassification = ["public", "internal", "confidential", "restricted"]
  }
  tag_policy_content = jsonencode({
    tags = {
      for k, allowed in local.tag_policy_keys : k => merge(
        { tag_key = { "@@assign" = k } },
        allowed == null ? {} : { tag_value = { "@@assign" = allowed } },
        length(var.tag_policy_required_resource_types) == 0 ? {} : { report_required_tag_for = { "@@assign" = var.tag_policy_required_resource_types } },
      )
    }
  })
}
```

and `content = local.tag_policy_content` for `tag-policy` (delete `policies/tag-policy.json`). Variable:

```hcl
variable "tag_policy_required_resource_types" {
  description = "Resource types (service:type, for example ec2:instance, s3:bucket) for which the tag policy reports CostCenter, Environment, Owner and DataClassification as required (report_required_tag_for). Empty (default) = no required-tag reporting. Terraform enforces it at plan when a workspace sets TF_AWS_TAG_POLICY_COMPLIANCE=error."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.tag_policy_required_resource_types : can(regex("^[a-z0-9-]+:[A-Za-z0-9-]+$", t))])
    error_message = "tag_policy_required_resource_types entries must look like service:type (for example ec2:instance)."
  }
}
```

Config: `aws.tagging.required_for` (array of strings) feeds it through `envs/aws/organization`. Add `DataClassification` to `aws_default_tags` in `envs/aws/workload/providers.tf` from `aws.workload_environments.<env>.data_classification` (default `internal`).

Rego (`require_labels.rego`, replace `has_any` use):

```rego
gcp_required := {"environment", "cost-center", "owner"}

aws_required := {"Environment", "CostCenter", "Owner"}

present_keys(rc, attrs) := {k |
	some attr in attrs
	m := lib.after(rc, attr)
	is_object(m)
	some k, _ in m
}

any_unknown(rc, attrs) if {
	some attr in attrs
	lib.unknown(rc, attr)
}

deny contains msg if {
	some t in gcp_labelled_types
	some rc in lib.written_of_type(t)
	not any_unknown(rc, ["labels", "effective_labels"])
	missing := gcp_required - present_keys(rc, ["labels", "effective_labels"])
	count(missing) > 0
	msg := sprintf("%s: missing required labels %v", [rc.address, sort(missing)])
}

deny contains msg if {
	some t in aws_tagged_types
	some rc in lib.written_of_type(t)
	not any_unknown(rc, ["tags", "tags_all"])
	missing := aws_required - present_keys(rc, ["tags", "tags_all"])
	count(missing) > 0
	msg := sprintf("%s: missing required tags %v", [rc.address, sort(missing)])
}
```

`policies.hcl`: `require_labels` to `enforcement_level = "mandatory"` (D7). GCP providers: add `cost-center = local.cost_center` and `owner = local.owner` (lower-cased, label-safe: `lower(replace(x, "/[^a-z0-9_-]/", "-"))`) to `gcp_default_labels` in every GCP root, reading `org.cost_center` and `org.owner` (add to each root's `cfg`, defaulting to `platform` and `platform-team` as the AWS roots do).

GCP projects stage: environment object gains `data_classification` (default `internal`); host projects get `tag_bindings = { data_classification = local.org.tag_values["data-classification-${env.data_classification}"] }`; contract `tag_value_ids` gains `data_classification` (update the exact contract type at `envs/gcp/projects/outputs.tf:62` and `scripts/check-contracts.sh` expectations).

- [ ] **Step 4: Run, expect pass** (`opa test policies/opa policies/opa-destructive -v`, the Terraform suites, `make consistency` for the contract check).
- [ ] **Step 5: Docs.** Matrix GRD-09 becomes: "Tag policy at the org root: `CostCenter`, `Environment`, `Owner`, `DataClassification` (values `public`/`internal`/`confidential`/`restricted`); required-tag reporting for `aws.tagging.required_for` types, enforced at plan with `TF_AWS_TAG_POLICY_COMPLIANCE=error`. GCP: `data-classification` tag bound to every environment host project; OPA `require_labels` (mandatory) requires `environment`, `cost-center`, `owner` labels and the AWS keys." Path: `modules/aws/governance/organization-policy/main.tf` (`tag_policy_content`). `UPGRADING.md` `### All clouds`: "**`require_labels` is now mandatory (CMP-10, ARC-17).** A resource without the required tags or labels fails policy checks. Every root already sets them through provider defaults; resources that override `tags`/`labels` with an empty map, or use a provider without `default_tags`, fail. GCP resources gain `cost-center` and `owner` labels (in-place updates)."
- [ ] **Step 6: Commit** `feat(tags): required tag keys, data classification on both clouds, mandatory label policy (CMP-10, ARC-17)`

---

## Task 16: CMP-11. SaaS residency check and the third-party register

**Files:**
- Modify: `envs/saas/config.tf:41`, `envs/saas/variables.tf:92-100,211-220`, `envs/saas/main.tf`
- Modify: `config/landing-zone.schema.json` (`saas.allowed_regions`)
- Create: `docs/compliance/third-parties.md`
- Test: `envs/saas/tests/config.tftest.hcl`

- [ ] **Step 1: Failing tests**

```hcl
run "supabase_region_outside_allowed_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency.yaml"
    supabase_region          = "us-east-1"
  }

  expect_failures = [terraform_data.saas_residency_guard]
}

run "vercel_region_mapped_and_checked" {
  command = plan

  variables {
    landing_zone_config_path  = "tests/fixtures/landing-zone.saas-residency.yaml"
    vercel_serverless_region  = "iad1"
  }

  expect_failures = [terraform_data.saas_residency_guard]
}

run "eu_regions_pass" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.saas-residency.yaml"
    supabase_region          = "eu-west-2"
    vercel_serverless_region = "lhr1"
  }

  assert {
    condition     = local.saas_regions_outside_allowed == []
    error_message = "London Supabase and Vercel lhr1 (eu-west-2) must pass an eu-west-2 allow list."
  }
}
```

(Fixture: `saas.allowed_regions: [eu-west-1, eu-west-2]`, plus the existing minimal saas fixture content; reuse the file's mocks.)

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

```hcl
locals {
  # Vercel function regions -> the AWS region they run in (Vercel docs, "Regions").
  vercel_to_aws_region = {
    arn1 = "eu-north-1", bom1 = "ap-south-1", cdg1 = "eu-west-3", cle1 = "us-east-2", cpt1 = "af-south-1",
    dub1 = "eu-west-1", fra1 = "eu-central-1", gru1 = "sa-east-1", hkg1 = "ap-east-1", hnd1 = "ap-northeast-1",
    iad1 = "us-east-1", icn1 = "ap-northeast-2", kix1 = "ap-northeast-3", lhr1 = "eu-west-2", pdx1 = "us-west-2",
    sfo1 = "us-west-1", sin1 = "ap-southeast-1", syd1 = "ap-southeast-2",
  }
  saas_allowed_regions = coalesce(try([for r in local.lz.saas.allowed_regions : tostring(r)], null), try([for r in local.lz.aws.allowed_regions : tostring(r)], null), [])
  saas_regions_in_use = compact([
    local.enable_supabase ? local.supabase_region : "",
    local.enable_vercel ? lookup(local.vercel_to_aws_region, local.vercel_serverless_region, "unmapped:${local.vercel_serverless_region}") : "",
  ])
  saas_regions_outside_allowed = length(local.saas_allowed_regions) == 0 ? [] : [for r in local.saas_regions_in_use : r if !contains(local.saas_allowed_regions, r)]
}

resource "terraform_data" "saas_residency_guard" {
  input = local.saas_regions_in_use

  lifecycle {
    precondition {
      condition     = length(local.saas_regions_outside_allowed) == 0
      error_message = "SaaS data would be processed outside saas.allowed_regions (else aws.allowed_regions): ${join(", ", local.saas_regions_outside_allowed)}."
    }
  }
}
```

(Use the root's real local names for the region and enable flags: `grep -n "supabase_region\|vercel_serverless_region\|enable_supabase\|enable_vercel" envs/saas/config.tf envs/saas/main.tf`. Check the Vercel map against the module's own allowed list at `modules/vercel/project/variables.tf:80-87` and keep the two in step.) No allow list configured = no check (unchanged behaviour).

- [ ] **Step 4: Write `docs/compliance/third-parties.md`** with this structure and content:

```markdown
# Third parties, subprocessors and exit plans

DORA Art. 28(3) requires a register of information on ICT third-party
providers; GDPR Art. 28 requires processor terms and a subprocessor list; HIPAA
164.308(b) requires a business associate agreement (BAA); PCI DSS 12.8 requires
a list of third-party service providers and their responsibilities. This page is
the landing zone's starting register. Copy it into your GRC tool and keep it
current.

| Provider | Service used here | Data it can hold | Region control in this repo | Assurance to collect | BAA / DPA | Exit plan |
|:--|:--|:--|:--|:--|:--|:--|
| Google Cloud | All GCP roots | Everything you deploy on GCP | `gcp.resourceLocations` org policy (GRD-01) | SOC 2 Type II, ISO 27001/17/18, PCI AoC (Compliance Reports Manager) | Cloud Data Processing Addendum; HIPAA BAA available | Terraform code is portable; data export per service; KMS keys cannot leave Cloud KMS (HSM keys excepted with Cloud EKM) |
| Amazon Web Services | All AWS roots | Everything you deploy on AWS | Region SCP (GRD-06) | AWS Artifact reports | AWS DPA; AWS BAA via Artifact | Same as above; Backup copies can be restored only in AWS |
| HashiCorp (HCP Terraform) | State, runs, variables | Terraform state (may hold secrets, see CHG-03), variables | HCP region choice at org creation (not in code) | HCP Trust Center reports | HashiCorp DPA | `state-backup.yml` exports every state version to your own WORM buckets; audit trail export (CHG-07) |
| GitHub | Code, CI | Source, CI logs, OIDC tokens | n/a | GitHub SOC reports | GitHub DPA | Git is portable; workflows are plain YAML |
| Supabase | `envs/saas` | Application database and auth data | `saas.allowed_regions` check (this task) | Supabase SOC 2 Type II | Supabase DPA; HIPAA BAA only on the plan that offers it (check before storing PHI) | `pg_dump` plus storage export; schedule it, it is not automated here |
| Vercel | `envs/saas` | Front-end code, function logs, environment variables | `saas.allowed_regions` check (functions only; the edge network is global) | Vercel SOC 2 Type II | Vercel DPA; HIPAA BAA only on the plan that offers it | Framework code is portable; move DNS and env vars |

## What you must still do
- Confirm each provider's current subprocessor list and notification process.
- Sign the BAA before PHI reaches a provider; Supabase and Vercel BAAs depend on plan tier.
- For DORA: classify which providers support critical or important functions,
  record contractual provisions (Art. 30) and test the exit plan.
- Review the reports yearly (SOC 2 CC9.2, ISO A.5.19 to A.5.22).
```

- [ ] **Step 5:** `make test TEST_DIRS=envs/saas TERRAFORM=$TF`, `make config-check`, `make links`. Matrix: new row **DP-09 SaaS residency check** (Default: On when `saas.allowed_regions` or `aws.allowed_regions` is set; SOC 2 C1.1; ISO A.5.34; NIST SA-9(5)); organizational row "Vendor management" links `third-parties.md`.
- [ ] **Step 6: Commit** `feat(saas): residency check against allowed regions; third-party register (CMP-11)`

---

## Task 17: CMP-12. GCP key protection and CMEK for regulated databases

**Files:**
- Modify: `modules/gcp/stages/organization/main.tf:81-92` (audit keys), `variables.tf` (gcp object `audit_key_protection_level`)
- Modify: `modules/gcp/data/cloud-sql/main.tf`, `variables.tf` (`require_cmek`)
- Modify: `modules/gcp/stages/app-services/main.tf:398-420`, `variables.tf` (`require_database_cmek`), `modules/gcp/stages/environment` pass-through, `envs/gcp/workload` (regulated sets it)
- Test: `modules/gcp/data/cloud-sql/tests/variables_validation.tftest.hcl`, `modules/gcp/stages/organization/tests/plan_assertions.tftest.hcl`

Irreversibility: `protection_level` lives on the key's version template and changing it replaces the key; the KMS module sets `prevent_destroy`, so an existing estate gets a plan error, not a lost key. The new setting therefore applies only where audit keys are created fresh (a new estate, or a new logging project from Task 8). KMS placement: the audit keys already move to the logging project when `logging_project_id` is set (G4); Task 8 makes that required for regulated estates. The billing and SCC keys stay in the admin project (they encrypt admin-project resources).

- [ ] **Step 1: Failing tests**

cloud-sql `variables_validation.tftest.hcl`:

```hcl
run "require_cmek_without_key_fails" {
  command = plan

  variables {
    require_cmek = true
  }

  expect_failures = [terraform_data.cmek_guard]
}
```

Org stage (local, not nested):

```hcl
run "audit_keys_hsm" {
  command = plan

  variables {
    # The file-level gcp object (plan_assertions.tftest.hcl:26-35) plus the keys under test.
    gcp = {
      admin_email                           = "admin@acme.io"
      break_glass_user                      = "break-glass@acme.io"
      organization_admin_groups             = ["org-admins@acme.io"]
      billing_admin_groups                  = ["billing-admins@acme.io"]
      allowed_regions                       = ["europe-west1"]
      strict_folder_policy_environment_keys = ["prod"]
      budget_currency                       = "USD"
      alert_notification_emails             = ["secops@acme.io"]
      audit_key_protection_level            = "HSM"
      logging_project_id                    = "acme-logging"
      logging_project_number                = "222233334444"
    }
  }

  assert {
    condition     = alltrue([for k, v in local.audit_cmek_keys : v.protection_level == "HSM"])
    error_message = "audit keys must take audit_key_protection_level."
  }
}
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

cloud-sql:

```hcl
variable "require_cmek" {
  description = "Fail the plan unless encryption_key_name is set. Set for regulated environments. Adding a key to an existing instance replaces it, so turn this on before the first apply."
  type        = bool
  default     = false
  nullable    = false
}

resource "terraform_data" "cmek_guard" {
  count = var.require_cmek ? 1 : 0
  input = var.encryption_key_name

  lifecycle {
    precondition {
      condition     = var.encryption_key_name != null
      error_message = "require_cmek is true but encryption_key_name is null: regulated Cloud SQL must use a customer-managed key."
    }
  }
}
```

Org stage gcp object: `audit_key_protection_level = optional(string, "SOFTWARE")` with validation `SOFTWARE|HSM`; `audit_cmek_keys` entries gain `protection_level = var.gcp.audit_key_protection_level` (the kms module takes per-key `protection_level`, `modules/gcp/governance/kms/variables.tf:33`). Root: `gcp.audit_key_protection_level` in config and schema. App-services `require_database_cmek` passes `require_cmek` to each database; `envs/gcp/workload` sets it when `local.compliance_class == "regulated"`.

- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Docs.** Matrix DP-01: "Protection level `SOFTWARE` by default; `gcp.audit_key_protection_level: HSM` for audit keys created fresh (FIPS 140-2 Level 3, Cloud HSM)." DP-05: "CMEK required for `compliance_class: regulated`." `UPGRADING.md` `### GCP`: "**`audit_key_protection_level` (CMP-12).** Changing it on existing audit keys fails the plan (keys are never destroyed). Use it for a new estate or a new logging project only."
- [ ] **Step 6: Commit** `feat(gcp-kms): HSM option for audit keys and CMEK requirement for regulated Cloud SQL (CMP-12)`

---

## Task 18: CMP-13. Export the HCP Terraform audit trail to WORM storage

**Files:**
- Create: `.github/workflows/tfc-audit-trail.yml`
- Modify: `docs/runbooks/state-backup.md` (new section "Audit trail export"), `docs/guides/BRANCH_PROTECTION.md` only if it lists workflows, `.github/workflows` documentation list if any (`grep -rn "state-backup.yml" docs`)
- Test: `make ci`'s actionlint / yaml lint (`make lint` or the meta-lint target that covers workflows: `grep -n "actionlint\|yamllint" Makefile`)

Existing mechanism reused: `state-backup.yml` already writes to an Object Lock S3 bucket and a retention-locked GCS bucket through GitHub OIDC, in the `tfc-state-backup` environment, and fails closed. The new workflow copies its structure and its SHA-pinned `uses:` lines exactly. Difference: the audit-trail API needs an **organization** token (team tokens are refused) and an HCP Terraform tier with audit logging; the workflow checks the entitlement and fails with a clear message when it is missing.

- [ ] **Step 1: Write the workflow**

```yaml
name: HCP Terraform Audit Trail Export

# Exports the HCP Terraform organization audit trail (who ran, approved,
# changed variables, teams and policies) to the same write-once buckets as
# state-backup.yml, under tfc-audit/. Evidence for SOC 2 CC8.1, ISO A.8.15,
# NIST AU-9(2) and PCI DSS 10.3.3.
#
# Source: secrets.TFC_TOKEN_AUDIT_TRAIL (organization token; the audit-trail
# API refuses team and user tokens). Lives in the tfc-audit-trail environment.
# Needs the org entitlement audit-logging (checked below).
# Targets: the STATE_BACKUP_* repository variables (see state-backup.yml).
# Window: the last 26 hours on each daily run (overlap; objects are keyed by
# event id so a duplicate overwrites nothing on a locked bucket and is skipped).

on:
  schedule:
    - cron: '45 5 * * *'
  workflow_dispatch:

permissions: {}

concurrency:
  group: tfc-audit-trail
  cancel-in-progress: false

jobs:
  export:
    name: Export audit trail
    runs-on: ubuntu-latest
    environment: tfc-audit-trail
    timeout-minutes: 30
    permissions:
      id-token: write
    steps:
      # Copy the harden-runner, configure-aws-credentials and google-github-actions/auth
      # steps from state-backup.yml verbatim (same pinned SHAs).
      - name: Check entitlement and fetch events
        env:
          TFC_TOKEN: ${{ secrets.TFC_TOKEN_AUDIT_TRAIL }}
          TFC_ORG: ${{ vars.TFC_ORGANIZATION }}
        run: |
          set -euo pipefail
          [ -n "${TFC_TOKEN}" ] || { echo "::error::TFC_TOKEN_AUDIT_TRAIL is not set"; exit 1; }
          api="https://app.terraform.io/api/v2"
          hdr=(-H "Authorization: Bearer ${TFC_TOKEN}" -H "Content-Type: application/vnd.api+json")
          ent="$(curl -fsS "${hdr[@]}" "${api}/organizations/${TFC_ORG}/entitlement-set" | jq -r '.data.attributes["audit-logging"]')"
          [ "${ent}" = "true" ] || { echo "::error::The HCP Terraform organization has no audit-logging entitlement"; exit 1; }
          since="$(date -u -d '26 hours ago' +%Y-%m-%dT%H:%M:%S.000Z)"
          page=1; : > events.ndjson
          while :; do
            body="$(curl -fsS "${hdr[@]}" "${api}/organization/audit-trail?since=${since}&page%5Bnumber%5D=${page}&page%5Bsize%5D=1000")"
            jq -c '.data[]' <<<"${body}" >> events.ndjson
            next="$(jq -r '.pagination.next_page // empty' <<<"${body}")"
            [ -n "${next}" ] || break
            page="${next}"
          done
          echo "events=$(wc -l < events.ndjson)" >> "${GITHUB_OUTPUT}"
      - name: Write to WORM targets
        run: |
          set -euo pipefail
          day="$(date -u +%Y/%m/%d)"
          key="tfc-audit/${{ vars.TFC_ORGANIZATION }}/${day}/run-${{ github.run_id }}.ndjson"
          if [ -n "${{ vars.STATE_BACKUP_S3_BUCKET }}" ]; then
            aws s3api put-object --bucket "${{ vars.STATE_BACKUP_S3_BUCKET }}" --key "${key}" --body events.ndjson
          fi
          if [ -n "${{ vars.STATE_BACKUP_GCS_BUCKET }}" ]; then
            gcloud storage cp --no-clobber events.ndjson "gs://${{ vars.STATE_BACKUP_GCS_BUCKET }}/${key}"
          fi
```

Check the audit-trail response shape (`pagination` location, `next_page` key) against the HCP Terraform API docs during implementation and adjust the `jq` paths; the step must fail, not silently write an empty file, if the shape differs (`jq -e`).

- [ ] **Step 2:** run the repo's workflow lint (`make lint` / meta-lint) and `make links`. Expected pass.
- [ ] **Step 3: Docs.** `state-backup.md` new section: token creation (organization token, stored only in the `tfc-audit-trail` environment restricted to `main`), entitlement check, bucket prefix, how to query (`aws s3 cp s3://<bucket>/tfc-audit/<org>/2026/11/12/ - | jq`). Matrix: new row **CHG-07 HCP Terraform audit trail export** (Default: Off until the secret is set; SOC 2 CC8.1, CC7.2; ISO A.8.15, A.8.32; NIST AU-9(2), AU-6; PCI 10.3.3).
- [ ] **Step 4: Commit** `feat(ci): export the HCP Terraform audit trail to WORM storage (CMP-13)`

---

## Task 19: CMP-14. Keep broad write permission sets out of production accounts

**Files:**
- Modify: `envs/aws/identity/config.tf`, `variables.tf`, `main.tf:41-67`
- Test: `envs/aws/identity/tests/variables_validation.tftest.hcl` (or `groups.tftest.hcl`; reuse its organization-contract override)

- [ ] **Step 1: Failing tests**

```hcl
run "developer_in_prod_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.prod-accounts.yaml"
    identity_groups = {
      "app-developers" = [{ permission_set = "Developer", accounts = ["workload_prod"] }]
    }
  }

  expect_failures = [terraform_data.production_assignment_guard]
}

run "developer_in_dev_passes" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.prod-accounts.yaml"
    identity_groups = {
      "app-developers" = [{ permission_set = "Developer", accounts = ["workload_dev"] }]
    }
  }

  assert {
    condition     = local.restricted_production_assignments == []
    error_message = "Developer in a non-production account must stay allowed."
  }
}

run "explicit_exception_allows" {
  command = plan

  variables {
    landing_zone_config_path              = "tests/fixtures/landing-zone.prod-accounts.yaml"
    production_restricted_permission_sets = []
    identity_groups = {
      "app-developers" = [{ permission_set = "Developer", accounts = ["workload_prod"] }]
    }
  }

  assert {
    condition     = local.restricted_production_assignments == []
    error_message = "an empty restricted list is the explicit, reviewable opt-out."
  }
}
```

(Fixture: `aws.workload_environments` `dev` (`account_key: workload_dev`) and `prod` (`account_key: workload_prod`, `is_production: true`); the test's organization contract has both account keys.)

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

`config.tf` `cfg`:

```hcl
    production_account_keys = try([
      for k, e in local.lz.aws.workload_environments : tostring(e.account_key)
      if coalesce(try(tobool(e.is_production), null), can(regex("^prod(uction)?$", k)))
    ], [])
```

(The production rule matches `envs/aws/network/config.tf:49-52`; IAC-1 in another workstream will unify it.)

`variables.tf`:

```hcl
variable "production_restricted_permission_sets" {
  description = "Permission sets that must not be assigned in production workload accounts (CMP-14). Default [\"Developer\"] (PowerUserAccess). Use PlatformAdmin or a scoped set there. An empty list is the explicit opt-out."
  type        = list(string)
  default     = ["Developer"]
  nullable    = false
}

variable "production_account_keys" {
  description = "Account keys treated as production for the assignment guard. Null = the account_key of every production entry in aws.workload_environments."
  type        = list(string)
  default     = null
}
```

`main.tf`:

```hcl
locals {
  production_account_keys = coalesce(var.production_account_keys, local.cfg.production_account_keys)
  production_account_ids  = [for k in local.production_account_keys : lookup(local.org.account_ids, k, "")]
  restricted_production_assignments = sort([
    for key, a in local.assignments : key
    if contains(var.production_restricted_permission_sets, a.permission_set) && (
      contains(local.production_account_keys, coalesce(a.account_key, "-")) ||
      contains(local.production_account_ids, coalesce(a.account_id, "-"))
    )
  ])
}

resource "terraform_data" "production_assignment_guard" {
  input = local.restricted_production_assignments

  lifecycle {
    precondition {
      condition     = length(local.restricted_production_assignments) == 0
      error_message = "These assignments give a restricted permission set (${join(", ", var.production_restricted_permission_sets)}) in a production account: ${join(", ", local.restricted_production_assignments)}. Use a read-only or scoped set, or change production_restricted_permission_sets with a recorded reason."
    }
  }
}
```

(`a.account_key`/`a.account_id` exist on explicit assignments; group-derived assignments carry `account_key` only. Use `try(a.account_id, null)` where a branch lacks the attribute.)

- [ ] **Step 4: Run, expect pass** (`make test TEST_DIRS=envs/aws/identity TERRAFORM=$TF`).
- [ ] **Step 5: Docs.** Matrix IAM-06 adds "A plan guard refuses `production_restricted_permission_sets` (default `Developer`) in production workload accounts." `UPGRADING.md` `### AWS`: "**Developer is refused in production accounts (CMP-14).** An existing assignment of `Developer` to a production account now fails the `aws-identity` plan. Move those users to a scoped set, or set `production_restricted_permission_sets = []` and record why."
- [ ] **Step 6: Commit** `feat(aws-identity): refuse broad write permission sets in production accounts (CMP-14)`

---

## Task 20: CMP-15 and CMP-16. File integrity, SCC tier, MFA: honest rows

Docs only. These controls have no Terraform API or need a host agent, so the
repo states the boundary instead of claiming them.

**Files:**
- Modify: `docs/compliance/control-matrix.md` (new rows DET-06, DET-07, IAM-15; "Organizational controls" rows), `docs/known-gaps.md` G10, `docs/runbooks/production-hardening.md` (two manual steps)

- [ ] **Step 1: Add these rows (exact text)**

| ID | Control | Cloud | Implementation (path · flag) | Default | Status | SOC 2 | ISO | NIST | CIS |
|:---|:--------|:------|:-----------------------------|:--------|:-------|:------|:----|:-----|:----|
| DET-06 | File integrity monitoring: **not provided.** GuardDuty Runtime Monitoring (DET-01) detects suspicious process and file behaviour but is not change detection of critical files. PCI DSS 11.5.2 needs an agent (for example a host-based FIM tool) that you deploy on the workload. SSM Inventory (VUL-04) records installed software, not file hashes. | AWS, GCP | Customer | n/a | n/a | CC7.1 | A.8.16 | SI-7 | n/a |
| DET-07 | Security Command Center tier: **manual.** Standard, Premium or Enterprise is activated in the console or through billing; there is no Terraform resource. The landing zone ships the findings topic (DET-03). Security Health Analytics custom modules (`google_scc_management_organization_security_health_analytics_custom_module`) need Premium and are not shipped. | GCP | Console: Security Command Center → Settings → Tier | Manual | n/a | CC7.1 | A.8.8 | CA-7, RA-5 | n/a |
| IAM-15 | MFA. AWS: alerts on console sign-in without MFA (LOG-10 EventBridge, LOG-09 CIS 4.2 alarm) and Security Hub CIS v3.0.0 MFA controls (DET-02). IAM Identity Center MFA enforcement and Google 2-Step Verification are set in the Identity Center console and the Google Admin console; neither has a Terraform API, so they are customer controls. | Both | `modules/aws/security/security-notifications` (`console-no-mfa`); Identity Center → Settings → Authentication; Google Admin → Security → 2-Step Verification | AWS alert On; enforcement Manual | Mock (alert) | CC6.1 | A.8.5 | IA-2(1), IA-2(2) | AWS 1.10 (via Security Hub) |

- [ ] **Step 2:** `production-hardening.md` gains two numbered manual steps (SCC tier with the console path and the evidence screenshot to keep; Identity Center "Require MFA: every time they sign in" plus Google 2SV enforcement), each with the evidence the auditor will ask for.
- [ ] **Step 3:** `make links`.
- [ ] **Step 4: Commit** `docs(compliance): state FIM, SCC tier and MFA boundaries (CMP-15, CMP-16)`

---

## Task 21: CMP-17 to CMP-20. Stale citations, SECURITY.md, region defaults

**Files:**
- Modify: `docs/compliance/control-matrix.md` (paths, duplicate ID, "Reviewed against" date)
- Modify: `SECURITY.md:52,57,63,64`
- Modify: `modules/gcp/stages/net-spoke/variables.tf:20,320,323`, `modules/gcp/stages/net-hub/variables.tf:20`, `modules/gcp/stages/dns-anchor/variables.tf:20`, `modules/gcp/stages/organization/variables.tf:75`
- Create: `scripts/check-matrix-paths.sh` and a Makefile hook in `links` (or in `consistency`)
- Test: the stage tests that rely on those defaults (`grep -rn "us-central1" modules/gcp/stages/*/tests`)

- [ ] **Step 1: Failing check script**

```bash
#!/usr/bin/env bash
# Fail when the control matrix cites a repo path that does not exist (CMP-17).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
fail=0
while IFS= read -r p; do
  case "$p" in
    modules/*|envs/*|policies/*|scripts/*|.github/*|docs/*|config/*|examples/*|templates/*)
      [ -e "$p" ] || { echo "control-matrix cites a missing path: $p"; fail=1; } ;;
  esac
done < <(grep -oE '`[A-Za-z0-9_./-]+/[A-Za-z0-9_./-]+`' docs/compliance/control-matrix.md docs/compliance/framework-crosswalk.md 2>/dev/null | cut -d: -f2- | tr -d '`' | sort -u)
dups="$(grep -oE '^\| [A-Z]+-[0-9]+ ' docs/compliance/control-matrix.md | sort | uniq -d)"
[ -z "$dups" ] || { echo "duplicate control IDs: $dups"; fail=1; }
exit "$fail"
```

Run `scripts/check-matrix-paths.sh`. Expected failure today: `policies/declarative-ec2.json`, `policies/rcp-data-perimeter.json.tftpl`, `policies/tag-policy.json`, and duplicate `IAM-14`. (`network/network-firewall` and similar relative module paths are not caught by the prefix filter; fix them by hand in Step 2.)

- [ ] **Step 2: Fix the matrix.** Replace `policies/declarative-ec2.json` with `modules/aws/governance/organization-policy/policies/declarative-ec2.json` (GRD-08, NET-07), `policies/rcp-data-perimeter.json.tftpl` with `modules/aws/governance/organization-policy/policies/rcp-data-perimeter.json.tftpl` (DP-04), the tag policy path per Task 15 (GRD-09), `network/network-firewall` with `modules/gcp/network/network-firewall` (LOG-06). Renumber the second `IAM-14` (GitHub Actions to AWS deploy roles) to `IAM-16` and update any references (`grep -rn "IAM-14" docs`). Update "Reviewed against the tree on" to the merge date.
- [ ] **Step 3: Fix `SECURITY.md`** (exact replacements):
  - Line 52: `- **Opt-in WORM retention**: \`gcp.enable_audit_bucket_lock\` locks the audit bucket's retention policy (irreversible). Without it, the bucket is versioned and access-controlled but not immutable. Regulated environments require it.`
  - Line 57: `- **VPC Flow Logs**: on every subnet, exported to a CMEK BigQuery dataset per environment (default 10% sampling, 30-day retention; 100% and 365 days for regulated environments).`
  - Line 63: `- **Cloud Audit Logs**: Data Access logs on for all services; retention set by \`compliance.audit_log_retention_days\` (default 365 days), with framework floors enforced at plan (PCI DSS 365, HIPAA 2190, FedRAMP Moderate 913).`
  - Line 64: `- **Security Command Center**: a Pub/Sub notification of every ACTIVE finding (CMEK topic). The SCC tier is activated outside Terraform.`
- [ ] **Step 4: Region defaults (CMP-20).** Change `net-spoke` `bigquery_location` and `storage_location` defaults from `"US"` to `null` and resolve them as `coalesce(var.flow_logs_export.bigquery_location, var.region)` in `main.tf`; remove the `us-central1` defaults from `net-hub`, `net-spoke`, `dns-anchor` `region` (make them required: every caller already passes a region, check with `grep -rn 'source *= *"../net-hub"\|net-spoke"\|dns-anchor"' modules envs`); org stage `allowed_regions` default becomes `["europe-west2"]` to match `default_region`. Test (net-spoke):

```hcl
run "flow_log_export_follows_region" {
  command = plan

  variables {
    region           = "europe-west2"
    flow_logs_export = { enabled = true, create_bigquery_dataset = true }
  }

  assert {
    condition     = local.flow_logs_bigquery_location == "europe-west2"
    error_message = "the flow-log export must default to the spoke's region, not US."
  }
}
```

(Merge with the file's required variables; name the new local `flow_logs_bigquery_location`.)
- [ ] **Step 5:** run `scripts/check-matrix-paths.sh` (pass), `make test TEST_DIRS="modules/gcp/stages/net-spoke modules/gcp/stages/net-hub modules/gcp/stages/dns-anchor modules/gcp/stages/organization" TERRAFORM=$TF`, `make docs`, `make links`.
- [ ] **Step 6: Docs.** `UPGRADING.md` `### GCP`: "**No US defaults in GCP stages (CMP-20).** `net-hub`, `net-spoke` and `dns-anchor` now require `region`; flow-log export locations default to that region; the org stage `allowed_regions` default is `[\"europe-west2\"]`. Roots already pass these values; only direct stage callers change. An existing flow-log dataset created in `US` would be replaced if its location changes: pin `bigquery_location = \"US\"` to keep it."
- [ ] **Step 7: Commit** `fix(compliance): correct matrix paths, SECURITY.md claims and US region defaults (CMP-17 to CMP-20)`

---

## Task 22: Accept GovCloud and EU sovereign partitions in validations

Scope: unblock, not support. After this task the validations no longer reject
`aws-us-gov` regions or the `aws-eusc` partition. Nothing is tested against
those partitions; several services this zone enables (for example Security
Lake, Macie, some GuardDuty features) may be missing there. The docs say so.

**Files:**
- Modify: the 23 regex occurrences of `aws(-us-gov|-cn)` in the 12 files listed by `grep -rln 'aws(-us-gov|-cn)' modules envs scripts templates`
- Modify: the canonical region regex everywhere `scripts/check-consistency.sh:13-16` checks it, and the check itself
- Modify: `config/landing-zone.schema.json` region patterns (`org.regions.aws`, `aws.allowed_regions`, `aws.enabled_regions`)
- Test: one `variables_validation.tftest.hcl` run per touched module family; `modules/aws/stages/organization/tests/variables_validation.tftest.hcl` shown

- [ ] **Step 1: Failing tests**

```hcl
run "accepts_govcloud_and_eusc_arns" {
  command = plan

  variables {
    terraform_run_role_arn = "arn:aws-eusc:iam::111111111111:role/tfc-run-role"
    break_glass_role_arn   = "arn:aws-us-gov:iam::111111111111:role/break-glass"
  }

  assert {
    condition     = true
    error_message = "the sovereign and GovCloud partitions must pass ARN validation."
  }
}
```

And in `envs/aws/network/tests/variables_validation.tftest.hcl`:

```hcl
run "accepts_govcloud_region" {
  command = plan

  variables {
    aws_region = "us-gov-west-1"
  }

  assert {
    condition     = local.aws_region == "us-gov-west-1"
    error_message = "GovCloud region names must pass the region validation."
  }
}
```

(If this root's plan fails later for an unrelated reason, such as AZ names derived from the region (ARC-3, another workstream), move this run to a module whose only region input is the validated one, for example `modules/aws/stages/organization` `aws_region`.)

- [ ] **Step 2: Run, expect failure** (validation error on both).
- [ ] **Step 3: Implement.** Partition alternation `aws(-us-gov|-cn)?` becomes `aws(-us-gov|-cn|-eusc|-iso|-iso-b)?` (sed across the listed files, then review each hit by hand). Canonical region regex becomes `^[a-z]{2,4}(-[a-z]+){1,2}-[1-9][0-9]?$` (accepts `eu-west-2`, `us-gov-west-1`, `eusc-de-east-1`; rejects `eu-west-0`). Update `check-consistency.sh` to enforce the new single form. Every RE2 repeat stays under 1000.
- [ ] **Step 4: Run, expect pass**; `make consistency`; `make config-check`.
- [ ] **Step 5: Docs.** In the crosswalk's "Out of scope" section (Task 23): "GovCloud and the AWS European Sovereign Cloud now pass input validation only. They are untested; service availability differs; FIPS endpoints are not configured (`use_fips_endpoint` is not set on any provider)."
- [ ] **Step 6: Commit** `fix(aws): accept GovCloud and EU sovereign partitions and region names in validations`

---

## Task 23: Framework crosswalks

Docs only, plus Task 21's path check covering the new file.

**Files:**
- Create: `docs/compliance/framework-crosswalk.md`
- Modify: `docs/compliance/README.md` (table row), `docs/compliance/control-matrix.md` intro (link), `docs/architecture/landing-zone-conformance.md` (link)

Rules for every row: the requirement ID as the framework numbers it; the matrix
control IDs; the code path; the **default state** (On, Off, Preset, Regulated,
Customer, Manual); and the customer share. "Regulated" means on for
`compliance_class: regulated` only.

- [ ] **Step 1: Write the document with this content**

```markdown
# Framework crosswalk

Maps framework requirements to the controls in the [control matrix](control-matrix.md).
Design evidence only (see the matrix's "Read this first"). Version cited:
PCI DSS v4.0.1 (June 2024); HIPAA Security Rule 45 CFR Part 164 Subpart C as in
force (the 2025 NPRM is not final); DORA Regulation (EU) 2022/2554 with its RTS
and ITS; NIST SP 800-53 Rev 5; FedRAMP Rev5 Moderate baseline; ISO/IEC
27001:2022 Annex A.

## PCI DSS v4.0.1

| Req. | Requirement (short) | Controls | Code | Default | You still do |
|:--|:--|:--|:--|:--|:--|
| 1.2, 1.3 | Network security controls, restrict CDE traffic | NET-01, NET-02, NET-05, NET-11 | `modules/gcp/stages/net-hub`, `modules/aws/stages/network-hub` | On; egress gate in production; Regulated | Define the CDE and segment it inside the environment; segmentation testing (11.4.5) |
| 1.4 | Controls between trusted and untrusted networks | NET-03, NET-07, NET-09 | `modules/gcp/network/cloud-armor`, `policies/declarative-ec2.json` path in matrix | Preset / On / Off | Edge for each public app |
| 2.2 | Secure configuration standards | GRD-01, GRD-08, VUL-06 | org policies, declarative EC2 policy | On | Workload hardening |
| 3.5, 3.6, 3.7 | Protect stored account data; key management | DP-01, DP-02, GRD-04, DP-05 | `modules/gcp/governance/kms`, `modules/aws/data/kms-key` | On (keys); CMEK org policy Preset; Cloud SQL CMEK Regulated | PAN rendering, key custodians, crypto-period policy |
| 4.2.1 | Strong cryptography in transit | DP-04, GRD-07 | RCP `RequireSecureTransport`; app-ingress SSL policy | On | TLS on your own endpoints |
| 5.2, 5.3 | Anti-malware | DET-01 (GuardDuty malware protection) | `modules/aws/security/guardduty-org` | On (EBS malware: production profile) | Anti-malware on GCP VMs and in containers |
| 6.3.3 | Critical patches within one month | VUL-04, VUL-05 | `modules/aws/ops/systems-manager`, `modules/gcp/ops/os-config` | On | Patch evidence per instance; exceptions |
| 6.4.1, 6.4.2 | Protect public web apps | NET-03, NET-09 | Cloud Armor, CloudFront + WAF | Preset / Off | Turn on for every public app |
| 7.2 | Least-privilege access | IAM-02, IAM-05, IAM-06, IAM-15 | stages, identity root | On | Access approval and review |
| 8.4.2 | MFA for all CDE access | IAM-15 | Identity Center / Google Admin | Manual | Enforce MFA in the IdP |
| 10.2 | Audit logs for all components | LOG-01, LOG-07, LOG-13, LOG-06 | `modules/gcp/governance/cloud-audit-logs`, `modules/aws/security/cloudtrail-org` | On | Application logs |
| 10.3.3, 10.3.4 | Logs backed up to a central store; integrity | LOG-02, LOG-03, LOG-07, LOG-08, CHG-07 | log archive, audit bucket | AWS On; GCP lock Regulated | Keep the lock on |
| 10.4.1 | Daily log review | LOG-05, LOG-09, LOG-10, DET-02 | alerts and Security Hub | On | Staffed review and tickets |
| 10.5.1 | Retain 12 months, 3 months immediately available | LOG-02, LOG-08 | `compliance.audit_log_retention_days` (floor 365 with `pci_dss`) | On (365) | Keep at or above 365 |
| 10.7.2 | Detect failures of critical security controls | LOG-05, GRD-05, DET-01 alerts on disablement | control-plane alerts, deny-tamper SCP | On | Respond to the alerts |
| 11.3 | Vulnerability scans | VUL-01, VUL-02, VUL-06 | Inspector, Artifact Analysis | On | Quarterly ASV external scans |
| 11.4 | Penetration testing | none | n/a | Customer | Annual and after significant change |
| 11.5.2 | Change-detection (FIM) | DET-06 | none | Customer | Deploy an FIM agent |
| 12.8 | Third-party service providers | DP-09, `third-parties.md` | `envs/saas` residency check | On when allowed regions set | TPSP list, responsibility matrix |
| 12.10.1 | Incident response plan | DET-05, regulatory runbook | `docs/runbooks/regulatory-notification.md` | Docs | Approve, test yearly, include brand notification |

## HIPAA Security Rule (45 CFR 164.308-316)

| Standard | Implementation spec | Controls | Default | You still do |
|:--|:--|:--|:--|:--|
| 164.308(a)(1)(ii)(A)-(B) | Risk analysis and management | VUL-06, DET-02 (inputs) | On | The risk analysis itself |
| 164.308(a)(1)(ii)(D) | Information system activity review | LOG-05, LOG-09, LOG-10, LOG-14 | On | Review and document |
| 164.308(a)(3), (a)(4) | Workforce access, access management | IAM-06, IAM-14, IAM-15 | On / Manual (MFA) | Joiner/mover/leaver |
| 164.308(a)(5)(ii)(C) | Log-in monitoring | LOG-09 (CIS 4.6 failed console auth), LOG-10 | On | Respond |
| 164.308(a)(6) | Security incident procedures | DET-05, regulatory runbook | On / Docs | Breach risk assessment |
| 164.308(a)(7)(ii)(A) | Data backup plan | BCK-01, BCK-03, BCK-04, BCK-07 | BCK-03 On; copy Off; GCP vault Regulated | Tag PHI resources `backup = true` |
| 164.308(a)(7)(ii)(B) | Disaster recovery plan | DR runbook, BCK-03 DR region | Docs / Off | Approve RTO/RPO |
| 164.308(a)(7)(ii)(D) | Testing and revision | BCK-02 | On with BCK-01 | Yearly DR exercise |
| 164.308(b)(1) | Business associate contracts | `third-parties.md` | Docs | Sign BAAs (AWS, Google, and Supabase/Vercel only on BAA-eligible plans) |
| 164.312(a)(1) | Access control | IAM-02, IAM-05, GRD-07 | On | |
| 164.312(a)(2)(iv) | Encryption at rest (addressable) | DP-01, DP-02, DP-03, GRD-04 | On; CMEK Preset/Regulated | Document the decision |
| 164.312(b) | Audit controls | LOG-01, LOG-07 | On | Application audit logs |
| 164.312(c)(1) | Integrity | LOG-07 (log file validation), LOG-03, LOG-08 | AWS On; GCP lock Regulated | |
| 164.312(d) | Person or entity authentication | IAM-01, IAM-05, IAM-15 | On / Manual | Enforce MFA |
| 164.312(e)(1), (e)(2)(ii) | Transmission security, encryption | DP-04, GRD-07 | On | |
| 164.316(b)(2)(i) | Retain documentation 6 years | LOG-02, LOG-08 with `hipaa` floor (2190) | Off until `compliance.frameworks: [hipaa]` | Set the framework |

## DORA (Regulation (EU) 2022/2554)

| Article | Requirement | Controls | Default | You still do |
|:--|:--|:--|:--|:--|
| Art. 6, 8 | ICT risk framework, identification and asset inventory | LOG-11 (Config), GRD-09 (tags), DP classification tag | On | The framework, its review |
| Art. 9(2)-(4) | Protection and prevention: access, encryption, network segmentation | IAM-*, DP-*, NET-*, GRD-* | On / Regulated | Policies, procedures |
| Art. 10 | Detection | DET-01, DET-02, DET-03, LOG-05 | On | 24/7 monitoring capability |
| Art. 11 | Response and recovery, BCP | DET-05, DR runbook | On / Docs | BCP, crisis communication |
| Art. 12(1)-(3) | Backup policies; restoration from backups segregated from the source | BCK-01 (separate account, locked), BCK-03 DR region, BCK-07 | Off (opt-in) | Turn on; define restoration procedures |
| Art. 12(6) | Restore tests | BCK-02 | On with BCK-01 | Record results |
| Art. 17 | ICT incident management process | regulatory runbook | Docs | Classification criteria |
| Art. 19 | Report major incidents (4 h / 72 h / 1 month) | regulatory runbook | Docs | Submit reports |
| Art. 24-25 | Digital operational resilience testing | BCK-02, tabletop (runbook section 6) | Partial | TLPT where required (Art. 26) |
| Art. 28(3) | Register of information | `third-parties.md` | Docs | Maintain the register in the ESA template |
| Art. 28(8) | Exit strategies | `third-parties.md` exit column, `state-backup.yml` | Docs / On | Test the exit plan |
| Art. 30 | Key contractual provisions | none | Customer | Contracts |

## NIST SP 800-53 Rev 5 (additions to the matrix columns)

The matrix already maps every row to Rev 5 controls. Families this work adds or
changes: AU-9(2) and AU-11 (CHG-07, configurable retention), CP-6 and CP-9(8)
(BCK-01, BCK-03), SC-8(1) and SC-13 (TLS 1.2 floor, HSM option), SI-2(2) (patch
install association), SA-9(5) (SaaS residency check), AC-6(5) (production
permission-set guard). Not covered: SI-7(1) on hosts (no FIM), IA-2(1)
enforcement (IdP side), SC-13 FIPS-validated endpoints.

## FedRAMP Moderate (Rev5)

FedRAMP authorization is **out of scope** (see below). For teams using the
Moderate baseline as a reference only:

| Control | FedRAMP parameter or expectation | Landing-zone state |
|:--|:--|:--|
| AU-11 | Retain per OMB M-21-31 (12 months active, 18 months cold) | `compliance.frameworks: [fedramp_moderate]` raises the floor to 913 days |
| AU-9(4) | Separate audit-management privilege | LOG-04 (GCP logging project), log-archive account (AWS) |
| CM-7(2) | Prevent unauthorized software | GRD-08 Allowed AMIs in audit mode only |
| IR-6 | Report to US-CERT/CISA within 1 hour | Runbook table lists it; no automation |
| SC-13 | FIPS-validated cryptography | Not configured: no FIPS endpoints; GCP Cloud HSM is FIPS 140-2 L3 (`audit_key_protection_level: HSM`) |
| SI-4(4), SI-4(5) | Inbound and outbound traffic monitoring | NET-05 (AWS), Cloud Armor and flow logs (GCP) |

## ISO/IEC 27001:2022

The matrix's ISO column is the crosswalk for Annex A. This work adds: A.5.19 to
A.5.22 (`third-parties.md`), A.5.24 to A.5.26 (regulatory runbook), A.5.29 and
A.5.30 (DR runbook and BCK-01), A.5.12 and A.5.13 (classification tag), A.8.13
(BCK-01, BCK-07), A.8.24 (TLS floor, HSM option).

## Out of scope (stated plainly)

| Regime or capability | Why | What would change it |
|:--|:--|:--|
| FedRAMP Moderate or High authorization, DoD IL4/IL5 | Needs an authorized boundary, FIPS endpoints, GovCloud or Assured Workloads, continuous monitoring deliverables | A dedicated fork on GovCloud and Assured Workloads |
| Google Assured Workloads (FedRAMP, CJIS, ITAR, EU data boundary) | No `google_assured_workloads_workload` in this repo | A new organization stage option creating the folder through Assured Workloads |
| AWS European Sovereign Cloud, GovCloud | Validations accept them (Task 22); nothing is tested there and some services are missing | Sandbox in the partition |
| Google sovereign offers (for example partner-operated clouds) | Different control plane and APIs | Out of scope |
| HITRUST, SOX ITGC | Certification programmes over your organization, not code | Your audit |
| PCI cardholder-data segmentation inside an environment | The regulated class is per environment, not per subnet or tier | Per-tier firewall policies with tag-based rules |
```

- [ ] **Step 2:** add the crosswalk to `docs/compliance/README.md`; `scripts/check-matrix-paths.sh` (Task 21) also scans this file; `make links`.
- [ ] **Step 3: Commit** `docs(compliance): PCI DSS, HIPAA, DORA, FedRAMP Moderate and ISO crosswalks with defaults`

---

## Order and dependencies

1. Critical: T1 (its Step 0 lands the `compliance` schema every later task reads), T2, T3, T4, T5, T6.
2. High: T7, T8, T9, T10, T11 (needs T5 schema), T12 (needs T11 `compliance_class`), T13, T14 (needs T2).
3. Medium/Low: T15, T16, T17 (needs T11), T18, T19, T20, T21, T22, T23 (last: it cites every new row).

Cross-workstream dependencies: ARC-13 (VPC-SC ingress identities, before a
regulated GCP env can enforce), IAC-1 (one production rule; T19 and T11 reuse the
network root's rule until then), CICD-11 (`destroy_guard` should also cover
`aws_backup_vault`, `aws_backup_vault_lock_configuration`,
`google_backup_dr_backup_vault`, the new copy vault).

## Evidence an auditor can collect

Run after apply. Name each artifact by control ID.

| Control | Evidence command or console path |
|:--|:--|
| BCK-01 copy vault locked | `aws backup describe-backup-vault --backup-vault-name org-backup-copy-vault` (fields `Locked: true`, `MinRetentionDays`, `LockDate`, `EncryptionKeyArn`) in the backup account; `aws backup get-backup-vault-access-policy --backup-vault-name org-backup-copy-vault` |
| BCK-01 cross-account enabled | `aws backup describe-global-settings` in the management account (`isCrossAccountBackupEnabled: true`) |
| BCK-01, BCK-03 copies happen | `aws backup list-copy-jobs --by-destination-vault-arn <copy-vault-arn> --by-created-after <date>`; `aws backup list-recovery-points-by-backup-vault --backup-vault-name org-backup-copy-vault` |
| BCK-03 policy content | `aws organizations describe-policy --policy-id <id> --query Policy.Content` (look for `copy_actions`, `delete_after_days`) |
| BCK-02 restore tests | `aws backup list-restore-testing-plans`; `aws backup list-restore-jobs --by-restore-testing-plan-arn <arn>` (status COMPLETED, validation status) |
| BCK-04 Cloud SQL region | `gcloud sql instances describe <i> --format='value(settings.backupConfiguration.location)'` |
| BCK-07 GCP vault | `gcloud backup-dr backup-vaults describe <vault> --location=<region>` (`backupMinimumEnforcedRetentionDuration`, `accessRestriction`); `gcloud backup-dr backup-plan-associations list --location=<region>` |
| LOG-02, LOG-03 GCP retention and lock | `gcloud storage buckets describe gs://<audit-bucket> --format='json(retention_policy,lifecycle_config,soft_delete_policy)'` (`isLocked: true`, `retentionPeriod`) |
| LOG-04 separation of duties | `gcloud projects get-iam-policy <logging-project>` (the automation SA is not owner); `gcloud projects describe <logging-project>` |
| LOG-08 AWS log archive retention | `aws s3api get-object-lock-configuration --bucket <log-archive>` (`Mode: COMPLIANCE`, `Days`); `aws s3api get-bucket-lifecycle-configuration --bucket <log-archive>` |
| Retention floor enforced | The TFC run log of a plan with a too-low value (expected failure message), plus `config/landing-zone.yaml` `compliance.frameworks` |
| VUL-04 patching | `aws ssm list-associations --association-filter-list key=Name,value=AWS-RunPatchBaseline`; `aws ssm list-compliance-summaries --filters Key=ComplianceType,Values=Patch`; `aws ssm describe-instance-patch-states --instance-ids <ids>` |
| DP-04 GCP TLS | `gcloud compute ssl-policies describe <name>-tls` (`minTlsVersion: TLS_1_2`, `profile: MODERN`); `gcloud compute target-https-proxies describe <proxy> --format='value(sslPolicy)'`; `gcloud org-policies describe gcp.restrictTLSVersion --organization=<ORG_ID>`; external check `nmap --script ssl-enum-ciphers -p 443 <domain>` (no TLSv1.0/1.1) |
| LOG-10 security contact | `aws sns list-subscriptions-by-topic --topic-arn <security-notifications-topic>` (confirmed, non-placeholder endpoints) |
| NET-11 regulated GCP | `gcloud access-context-manager perimeters describe <perimeter> --policy=<policy>` (`status` populated, `useExplicitDryRunSpec` false); `gcloud compute networks subnets describe <subnet> --region=<r> --format='value(logConfig)'` (`flowSampling: 1.0`) |
| NET-11 regulated AWS | `aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].PolicyDocument'` (`aws:ResourceOrgID`); `aws network-firewall describe-firewall-policy --firewall-policy-name <n>` (`StatefulDefaultActions` contains `aws:drop_established`) |
| GRD-09 tags | `aws organizations describe-effective-policy --policy-type TAG_POLICY --target-id <account>`; Resource Groups Tagging API `aws resourcegroupstaggingapi get-compliance-summary`; TFC policy-check results for `require_labels` (mandatory) |
| GCP classification | `gcloud resource-manager tags bindings list --parent=//cloudresourcemanager.googleapis.com/projects/<n>` |
| DP-09 SaaS residency | TFC plan output of `envs/saas`; Supabase dashboard → Project Settings → General (region); Vercel → Project → Settings → Functions (region) |
| DP-01 HSM audit keys | `gcloud kms keys describe audit-logs --keyring=<prefix>-audit-cmek --location=<r> --project=<logging-project> --format='value(versionTemplate.protectionLevel)'` |
| DP-05 Cloud SQL CMEK | `gcloud sql instances describe <i> --format='value(diskEncryptionConfiguration.kmsKeyName)'` |
| CHG-07 TFC audit trail | `aws s3 ls s3://<state-backup-bucket>/tfc-audit/<org>/ --recursive`; GitHub Actions run history of `tfc-audit-trail.yml` |
| IAM-06 / CMP-14 guard | `aws sso-admin list-account-assignments --instance-arn <i> --account-id <prod-account> --permission-set-arn <developer-ps>` returns none |
| IAM-15 MFA | Identity Center console → Settings → Authentication (screenshot, "Every time they sign in"); Google Admin → Security → 2-Step Verification (screenshot, Enforcement on); Security Hub control `IAM.5`/`IAM.6`/`IAM.9` findings export |
| DET-07 SCC tier | Security Command Center → Settings → Tier (screenshot); `gcloud scc settings describe --organization=<ORG_ID>` if available in your gcloud version |
| Regulatory notification | The approved `docs/runbooks/regulatory-notification.md` with roles filled; tabletop record with date |
| DR objectives | `docs/runbooks/disaster-recovery.md` with measured RPO/RTO from the last exercise |
| Crosswalk accuracy | `scripts/check-matrix-paths.sh` output (exit 0) at the audit date |
