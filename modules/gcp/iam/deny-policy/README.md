# Google Cloud IAM Deny Policy Module

Creates [IAM deny policies](https://docs.cloud.google.com/iam/docs/deny-overview)
at an organization, folder, or project. Deny policies are a **coarse,
allow-independent backstop**: they block specific permissions for specific
principals regardless of the roles those principals hold. IAM evaluates **deny
before allow**, so a matching deny always wins, and deny policies attached high
in the hierarchy are inherited downward.

They are the defense-in-depth complement to Organization Policy constraints —
org policy restricts how resources may be *configured*; deny policies restrict
what actions a *principal* may take. See [`docs/known-gaps.md`](../../../../docs/known-gaps.md) (G9).

## Usage

```hcl
module "org_deny" {
  source = "../../iam/deny-policy"

  # URL-encoded attachment point — build with urlencode(...).
  parent = urlencode("cloudresourcemanager.googleapis.com/organizations/123456789")

  deny_policies = [
    {
      name         = "deny-sa-key-creation"
      display_name = "Deny service-account key creation to all but break-glass"
      rules = [
        {
          description        = "Only the break-glass group may create SA keys"
          denied_principals  = ["principalSet://goog/public:all"]
          denied_permissions = ["iam.googleapis.com/serviceAccountKeys.create"]
          exception_principals = [
            "principalSet://goog/group/break-glass@example.com",
          ]
        }
      ]
    }
  ]
}
```

`denied_principals` / `exception_principals` use the IAM v2 principal-set
syntax (e.g. `principalSet://goog/public:all`, `principal://...`,
`principalSet://goog/group/<email>`). `denied_permissions` use the
`service.googleapis.com/resource.action` form. An optional CEL
`denial_condition` scopes when the deny applies (e.g. by resource tag).

Passing an empty `deny_policies` list creates nothing — the module is inert by
default, so it is safe to wire unconditionally and populate later.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	parent = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_iam_deny_policy.this (modules/gcp/iam/deny-policy/main.tf#L8)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_parent"></a> [parent](#input\_parent) | URL-encoded attachment point for the deny policies — the full resource name with '/' encoded as '%2F', e.g. urlencode("cloudresourcemanager.googleapis.com/organizations/123456789"). Org, folder, or project. | `string` | n/a | yes |
| <a name="input_deny_policies"></a> [deny\_policies](#input\_deny\_policies) | IAM deny policies to create at the parent. Each has one or more rules; each rule denies a set of permissions for a set of principals, with optional exception principals/permissions and a CEL denial condition. Default [] = create nothing (inert). | <pre>list(object({<br/>    name         = string<br/>    display_name = optional(string)<br/>    rules = list(object({<br/>      description           = optional(string)<br/>      denied_principals     = list(string)<br/>      denied_permissions    = list(string)<br/>      exception_principals  = optional(list(string), [])<br/>      exception_permissions = optional(list(string), [])<br/>      denial_condition = optional(object({<br/>        expression  = string<br/>        title       = optional(string)<br/>        description = optional(string)<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_deny_policy_ids"></a> [deny\_policy\_ids](#output\_deny\_policy\_ids) | Map of deny-policy name to the created google\_iam\_deny\_policy resource ID. |
| <a name="output_deny_policy_names"></a> [deny\_policy\_names](#output\_deny\_policy\_names) | List of deny-policy names created. |
<!-- END_TF_DOCS -->
