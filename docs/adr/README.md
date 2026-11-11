# Architecture decision records

Each ADR records one decision as Context, Decision and Consequences, on one page or less. Status is Accepted (in effect), or Proposed (planned or design only; not yet implemented). Add new ADRs with the next free number and list them here.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-cloud-selection-by-workspace.md) | Cloud selection is which workspaces you apply | Accepted |
| [0002](0002-one-config-file.md) | One committed configuration file | Accepted |
| [0003](0003-cross-root-contracts.md) | Cross-root contracts | Accepted |
| [0004](0004-per-stage-identities.md) | Per-stage plan and apply identities | Accepted |
| [0005](0005-hcp-terraform-backend.md) | HCP Terraform as the default backend; Stacks deferred | Accepted |
| [0006](0006-persistent-sandbox.md) | Persistent sandbox estate, which also stages SCPs | Accepted |
| [0007](0007-administrator-access-boundary.md) | AdministratorAccess capped by boundary and SCPs | Accepted |
| [0008](0008-remote-state-reads.md) | Keep terraform_remote_state; ephemeral tfe_outputs for the SaaS bridge | Accepted |
| [0009](0009-aws-second-region.md) | AWS second region as a second network workspace | Proposed |
| [0010](0010-repo-wide-tags.md) | Repo-wide tags and labels | Accepted |
| [0011](0011-temporary-elevated-access.md) | Temporary elevated access to AWS accounts | Accepted |
| [0012](0012-cloudtrail-delegated-admin.md) | CloudTrail delegated administrator | Accepted |
| [0013](0013-security-hub-and-policy-language.md) | Security Hub generation and policy language | Accepted |
| [0014](0014-log-archive-bucket-policy.md) | Log-archive PutBucketPolicy stays allowed and is detected | Accepted |
| [0015](0015-team-owned-app-stacks.md) | Team-owned app stacks consume the environment contract | Proposed |
| [0016](0016-split-aws-organization-stage.md) | Split the AWS organization stage by concern | Proposed |
