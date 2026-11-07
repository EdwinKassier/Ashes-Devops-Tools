# Guardrails Stage Module

The org-node IAM deny policies of the GCP landing zone: the admin-containment
policy (`contain-admin-identity`) plus any caller-supplied `iam_deny_policies`.

## Purpose

- **Admin containment**: denies, to everyone except the break-glass principals,
  org-wide mutation of logging sinks, exclusions and log buckets and of VPC-SC
  perimeters, access levels and access policies; and, scoped by the
  `containment/protected` tag to the audit store, bucket delete/update/IAM
  change/untag, object delete, key-version destroy/disable and key/keyring IAM
  change.
- **Extra deny policies**: an allow-independent backstop for any other
  sensitive permission.
- **Break-glass spec**: `deny_policy_specs` renders each policy as a gcloud
  policy file for the emergency path.

## Separation of duties

The gcp-organization apply identity is the identity the containment policy
constrains, and a deny policy cannot protect itself (`iam.denypolicies.*` is not
deny-supported). In the default `guardrail_owner_mode = "separate"` this stage
runs in the `gcp-guardrails` root, which lives in its own HCP Terraform
project where only the security team can apply. It runs as the gcp-bootstrap
`<prefix>-guardrails-apply` SA, the only automation identity with
`roles/iam.denyAdmin`, WIF-bound to that workspace by immutable ID.

The legacy `guardrail_owner_mode = "organization"` calls this stage from the
organization stage with `create_deny_policies = false`. There it only renders
the policies, and the organization stage applies them with its own deny-policy
module, so existing state addresses do not move.

## Dependencies

The `containment/protected` tag is created and bound by the organization stage
(`enable_admin_containment`); pass its IDs in. The `envs/gcp/guardrails` root
looks them up under the organization rather than reading gcp-organization state.

## Usage

```hcl
module "guardrails" {
  source = "../../modules/gcp/stages/guardrails"

  org_id                        = "123456789012"
  enable_admin_containment      = true
  containment_exempt_principals = ["principalSet://goog/group/gcp-break-glass@acme.io"]
  containment_tag_key_id        = "tagKeys/281484271805521"
  containment_tag_value_id      = "tagValues/281479612808422"
}
```

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |



## Modules


- iam_deny - ../../iam/deny-policy




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Numeric GCP organization ID. The deny policies attach to this organization node. | `string` | n/a | yes |
| <a name="input_containment_exempt_principals"></a> [containment\_exempt\_principals](#input\_containment\_exempt\_principals) | Break-glass principals exempt from the admin-containment deny policy, as IAM v2 principal identifiers (e.g. principalSet://goog/group/break-glass@acme.com). Required (non-empty) when enable\_admin\_containment is true. | `list(string)` | `[]` | no |
| <a name="input_containment_tag_key_id"></a> [containment\_tag\_key\_id](#input\_containment\_tag\_key\_id) | ID of the containment tag key that marks the audit store (created and bound by the organization stage), as tagKeys/<n> or the bare <n>. Required when enable\_admin\_containment is true. | `string` | `null` | no |
| <a name="input_containment_tag_value_id"></a> [containment\_tag\_value\_id](#input\_containment\_tag\_value\_id) | ID of the containment/protected tag value, as tagValues/<n> or the bare <n>. Required when enable\_admin\_containment is true. | `string` | `null` | no |
| <a name="input_create_deny_policies"></a> [create\_deny\_policies](#input\_create\_deny\_policies) | Create the deny policies at the org node. false = only render them (outputs deny\_policies and deny\_policy\_specs) for a caller that applies them itself, as the organization stage does in its legacy guardrail\_owner\_mode = "organization". Default true. | `bool` | `true` | no |
| <a name="input_enable_admin_containment"></a> [enable\_admin\_containment](#input\_enable\_admin\_containment) | Create the admin-containment IAM deny policy (contain-admin-identity). For all principals except containment\_exempt\_principals (break-glass) it blocks, org-wide, sink update/delete, exclusion changes, log-bucket delete and VPC-SC perimeter, access-level and access-policy mutation. Scoped by the containment/protected tag to the audit store, it also blocks bucket delete/update/IAM change/untag, object delete, key-version destroy/disable and key and keyring IAM change. Once on, any change to a sink, exclusion or perimeter must be applied by break-glass. Default false. | `bool` | `false` | no |
| <a name="input_enable_principal_access_boundary"></a> [enable\_principal\_access\_boundary](#input\_enable\_principal\_access\_boundary) | The organization stage binds a principal access boundary to the automation service accounts. With containment on, its update, delete and unbind are then denied to all but break-glass. Keep it in step with the gcp-organization enable\_principal\_access\_boundary input. Default false. | `bool` | `false` | no |
| <a name="input_iam_deny_policies"></a> [iam\_deny\_policies](#input\_iam\_deny\_policies) | Extra IAM deny policies at the org node, created next to the containment policy: a coarse, allow-independent backstop that blocks specific permissions for specific principals regardless of the roles they hold. Default [] = none. | <pre>list(object({<br/>    name         = string<br/>    display_name = optional(string)<br/>    rules = list(object({<br/>      description           = optional(string)<br/>      denied_principals     = list(string)<br/>      denied_permissions    = list(string)<br/>      exception_principals  = optional(list(string), [])<br/>      exception_permissions = optional(list(string), [])<br/>      denial_condition = optional(object({<br/>        expression  = string<br/>        title       = optional(string)<br/>        description = optional(string)<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_containment_rules"></a> [admin\_containment\_rules](#output\_admin\_containment\_rules) | Rules of the admin-containment deny policy (empty when enable\_admin\_containment = false): denied permissions, exempt principals and whether the rule is tag-scoped to the audit store. |
| <a name="output_deny_policies"></a> [deny\_policies](#output\_deny\_policies) | Rendered deny policies (admin containment + iam\_deny\_policies), in the deny-policy module's input shape. The organization stage applies these itself in its legacy organization mode. |
| <a name="output_deny_policy_ids"></a> [deny\_policy\_ids](#output\_deny\_policy\_ids) | Map of deny-policy name to resource ID (empty when create\_deny\_policies = false). |
| <a name="output_deny_policy_names"></a> [deny\_policy\_names](#output\_deny\_policy\_names) | Names of the deny policies this stage creates at the org node (empty when create\_deny\_policies = false). |
| <a name="output_deny_policy_specs"></a> [deny\_policy\_specs](#output\_deny\_policy\_specs) | Map of deny-policy ID => gcloud policy-file JSON, for the break-glass path only: gcloud iam policies create\|update <id> --attachment-point=cloudresourcemanager.googleapis.com/organizations/<org> --kind=denypolicies --policy-file=<file>. |
| <a name="output_parent"></a> [parent](#output\_parent) | URL-encoded org attachment point of the deny policies. |
<!-- END_TF_DOCS -->
