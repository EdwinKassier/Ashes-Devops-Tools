# incident-response

AWS incident-response automation for the SRA landing zone: a
GuardDuty-triggered isolation Lambda plus an intra-org forensics role for
cross-account EBS-snapshot sharing. The whole module is **gated** behind
`enable_incident_response`.

## Auto-isolation flow

```text
GuardDuty finding (severity >= 7)
  -> EventBridge rule (ir-guardduty-high-severity)
    -> EventBridge target
      -> isolation Lambda (ir-isolate)
```

EventBridge is granted `lambda:InvokeFunction` on the isolation Lambda
(`aws_lambda_permission.eventbridge`), scoped to the rule ARN — without it the
rule/target exist but EventBridge is denied at invoke time and the finding is
silently dropped.

The Lambda (`files/isolate.py`) is an **isolation scaffold**: it logs the
finding and returns success. Extend it to attach the quarantine security group
(below) to the flagged instance and, for forensics, to share an EBS snapshot
with the forensics account.

## Quarantine security group

When `quarantine_vpc_id` is set, the module creates a **deny-all** security
group (`ir-quarantine-deny-all`) in that VPC — it declares *no* ingress or
egress rules, so AWS applies an implicit deny in both directions. The isolation
Lambda attaches this SG to a flagged instance's ENIs to cut off all traffic.
Left empty (the default), no SG is created (the VPC to quarantine into is a
per-deployment input).

## Forensics role (intra-org)

`ir-forensics-snapshot-share` is trusted only by the **forensics account**
principal AND further scoped by `aws:PrincipalOrgID` AND `aws:SourceAccount`
(belt-and-suspenders), so no principal outside the organization — and no
account other than the forensics account — can assume it even if the account id
leaks. It is intended for cross-account EBS-snapshot copy/share during an
investigation.

When `forensics_kms_key_arn` is set, the role additionally gets
`kms:Decrypt` / `kms:DescribeKey` / `kms:CreateGrant` on that key, scoped by
`aws:SourceOrgID`, so shared **encrypted** snapshots are actually usable in the
forensics account (without it, a shared encrypted snapshot is present but
unreadable).

## Delivered here vs per-workload

Delivered by this module (from the security-tooling account):

- The GuardDuty→EventBridge→Lambda auto-isolation path, with the invoke
  permission.
- The optional deny-all quarantine SG (gated on `quarantine_vpc_id`).
- The security-tooling-side `ir-forensics-snapshot-share` assume role and its
  optional forensics-KMS grant.

Deployed **per-workload** (NOT by this module):

- The reciprocal member-side snapshot-**share** roles/policies that permit
  `ec2:ModifySnapshotAttribute` to share encrypted snapshots back to the
  forensics account. Those live in each workload account's stack because they
  grant permissions on resources owned there.
- The extended isolation Lambda handler logic (this module ships the scaffold).

## Wiring

This module is wired by **C16** (the security stage), which supplies
`forensics_account_id`, `org_id`, `forensics_kms_key_arn` (the forensics CMK),
and optionally `quarantine_vpc_id`. Include it there rather than instantiating
it directly per account.

## Build artifact note

The `archive` provider packages `files/isolate.py` into `files/isolate.zip` at
plan/apply time. That zip is a **build artifact** and is intentionally not
committed (see the module `.gitignore`); only `isolate.py` is tracked.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.8.0 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_cloudwatch_event_rule.guardduty_high (modules/aws/incident-response/main.tf#L73)
- resource.aws_cloudwatch_event_target.isolate (modules/aws/incident-response/main.tf#L85)
- resource.aws_iam_role.forensics_snapshot (modules/aws/incident-response/main.tf#L129)
- resource.aws_iam_role.isolation_lambda (modules/aws/incident-response/main.tf#L22)
- resource.aws_iam_role_policy.forensics_kms (modules/aws/incident-response/main.tf#L155)
- resource.aws_lambda_function.isolate (modules/aws/incident-response/main.tf#L57)
- resource.aws_lambda_permission.eventbridge (modules/aws/incident-response/main.tf#L95)
- resource.aws_security_group.quarantine (modules/aws/incident-response/main.tf#L108)
- data source.archive_file.isolate (modules/aws/incident-response/main.tf#L14)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_incident_response"></a> [enable\_incident\_response](#input\_enable\_incident\_response) | Master switch for the incident-response automation. When false, no Lambda, EventBridge rule, or forensics role is created. | `bool` | `true` | no |
| <a name="input_forensics_account_id"></a> [forensics\_account\_id](#input\_forensics\_account\_id) | 12-digit AWS account ID of the forensics account that is trusted to assume the snapshot-sharing role. Required when enable\_incident\_response is true. | `string` | `""` | no |
| <a name="input_forensics_kms_key_arn"></a> [forensics\_kms\_key\_arn](#input\_forensics\_kms\_key\_arn) | ARN of the forensics CMK. When set, the forensics snapshot-sharing role is granted kms:Decrypt/DescribeKey/CreateGrant on it (scoped by aws:SourceOrgID) so shared encrypted snapshots are usable in the forensics account. Empty (default) omits the grant. | `string` | `""` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxx) used to scope the forensics role trust policy via aws:PrincipalOrgID and the forensics KMS grant via aws:SourceOrgID. | `string` | `""` | no |
| <a name="input_quarantine_vpc_id"></a> [quarantine\_vpc\_id](#input\_quarantine\_vpc\_id) | VPC ID in which the deny-all quarantine security group is created. Empty (default) skips the SG; supply the VPC that holds the workloads the isolation Lambda may need to quarantine. The Lambda attaches this SG to a flagged instance's ENIs to cut off all traffic. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_forensics_role_arn"></a> [forensics\_role\_arn](#output\_forensics\_role\_arn) | ARN of the forensics snapshot-sharing role, or null when disabled. |
| <a name="output_guardduty_rule_arn"></a> [guardduty\_rule\_arn](#output\_guardduty\_rule\_arn) | ARN of the EventBridge rule matching high-severity GuardDuty findings, or null when disabled. |
| <a name="output_isolation_lambda_arn"></a> [isolation\_lambda\_arn](#output\_isolation\_lambda\_arn) | ARN of the isolation Lambda, or null when incident response is disabled. |
| <a name="output_quarantine_security_group_id"></a> [quarantine\_security\_group\_id](#output\_quarantine\_security\_group\_id) | ID of the deny-all quarantine security group, or null when incident response is disabled or quarantine\_vpc\_id is unset. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "incident_response" {
  source = "../../modules/aws/incident-response"

  forensics_account_id = "333333333333"
  org_id               = "o-abc123def0"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
