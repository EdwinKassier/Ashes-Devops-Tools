# firewall-manager-org

AWS Firewall Manager (FMS) for the SRA landing zone. FMS enforces security
baselines — security-group audit/common policies, WAFv2 web ACLs, Route 53
Resolver DNS Firewall, and AWS Network Firewall — **org-wide** from a single
delegated administrator.

Prerequisites:

- **Trusted access** for `fms.amazonaws.com` must be enabled in the organization
  (see the org module).
- The Security Tooling account must be registered as the FMS **delegated
  administrator** (see task C8 / `security-delegated-admin`). This module's
  `aws_fms_admin_account` performs the FMS-specific admin-account registration
  from the organization **management** account (the aliased `aws.management`
  provider).

Once the admin account is registered, the FMS **policies** are created in the
FMS-admin (Security Tooling = default provider) account and applied across every
member account. Each policy in `fms_policies` pins a `resource_type`, an FMS
policy `type`, and the type-specific `managed_service_data` JSON blob.

`enable_firewall_manager` gates the whole module off.

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
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |
| <a name="provider_aws.management"></a> [aws.management](#provider\_aws.management) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_fms_admin_account.this (modules/aws/firewall-manager-org/main.tf#L8)
- resource.aws_fms_policy.this (modules/aws/firewall-manager-org/main.tf#L15)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_firewall_manager"></a> [enable\_firewall\_manager](#input\_enable\_firewall\_manager) | Master toggle for AWS Firewall Manager. When false the module creates neither the admin-account registration nor any FMS policies. | `bool` | `true` | no |
| <a name="input_fms_admin_account_id"></a> [fms\_admin\_account\_id](#input\_fms\_admin\_account\_id) | 12-digit account ID nominated as the Firewall Manager administrator (the Security Tooling account). Registered from the management account via the aliased provider. Required when enable\_firewall\_manager is true. | `string` | `""` | no |
| <a name="input_fms_policies"></a> [fms\_policies](#input\_fms\_policies) | Firewall Manager policies to enforce org-wide, keyed by policy name. Each policy pins a resource\_type, an FMS policy type (e.g. SECURITY\_GROUPS\_COMMON, WAFV2, DNS\_FIREWALL, NETWORK\_FIREWALL), an optional remediation flag, and the type-specific managed\_service\_data JSON blob. | <pre>map(object({<br/>    resource_type        = string<br/>    type                 = string<br/>    remediation_enabled  = optional(bool, true)<br/>    managed_service_data = optional(string)<br/>  }))</pre> | <pre>{<br/>  "security-group-audit": {<br/>    "managed_service_data": "{\"type\":\"SECURITY_GROUPS_COMMON\",\"securityGroups\":[{\"id\":\"sg-000000000000\"}],\"revertManualSecurityGroupChanges\":false,\"exclusiveResourceSecurityGroupManagement\":false,\"applyToAllEC2InstanceENIs\":false}",<br/>    "resource_type": "AWS::EC2::SecurityGroup",<br/>    "type": "SECURITY_GROUPS_COMMON"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_account_id"></a> [admin\_account\_id](#output\_admin\_account\_id) | The account ID registered as the Firewall Manager administrator, or null when Firewall Manager is disabled. |
| <a name="output_policy_ids"></a> [policy\_ids](#output\_policy\_ids) | Map of FMS policy name to policy ID for every policy created by this module. |
<!-- END_TF_DOCS -->
