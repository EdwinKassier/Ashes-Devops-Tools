# Guardrails Root

`envs/gcp/guardrails` (workspace `gcp-guardrails`) owns the org-node IAM deny
policies: the admin-containment policy and any `iam_deny_policies`. The
security team applies it. It replaces the manual `gcloud iam policies`
step that `guardrail_owner_mode = "separate"` used to need.

## How it is separated

- **Identity**: plan runs as `<prefix>-guardrails-plan` (read-only:
  `iam.denyReviewer`, `resourcemanager.tagViewer`) and apply as
  `<prefix>-guardrails-apply`, the only automation identity with
  `roles/iam.denyAdmin`. gcp-bootstrap binds both to this workspace by its
  immutable workspace ID only, never by name.
- **People**: tfc-admin puts the workspace in its own HCP Terraform project
  (`<prefix>guardrails`). The security team (`security_team_id`) has write
  access there and no other team has any. Speculative plans and auto-apply are
  off.
- **Inputs**: containment is authored from `config/landing-zone.yaml`
  (`org.domain`, `gcp.environments[*].is_production`, `gcp.admin_containment`,
  `gcp.break_glass_group`, `gcp.principal_access_boundary`). Extra deny
  policies (`iam_deny_policies`) live in a committed
  `envs/gcp/guardrails/guardrails.auto.tfvars`, which CODEOWNERS assigns to
  the platform and security teams (and `.gitignore` exempts). Do not set them
  as workspace variables: the security team's grant is variables read-only,
  and tfc-admin attaches no shared variable set here, so platform-controlled
  values cannot reach this workspace. The root never reads gcp-organization
  outputs; it looks up the org and the `containment/protected` tag directly.

## Order

Apply gcp-organization first. With containment on, it creates the
`containment/protected` tag and binds it to the audit store, and this root's
tag lookup fails until the tag exists. Both roots derive containment from the
same config keys, so they agree. Use this root only with
`guardrail_owner_mode = "separate"` (the default) in gcp-bootstrap and
gcp-organization.

## Break-glass

For an emergency change outside the security-team apply, a PAM-elevated
`guardrail_owner_members` member impersonates the guardrails SA and applies
`deny_policy_specs` with gcloud. See
[`docs/runbooks/break-glass.md`](../../../docs/runbooks/break-glass.md).

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |

## Modules


- guardrails - ../../../modules/gcp/stages/guardrails


## Resources

The following resources are created:


- data source.google_organization.org (envs/gcp/guardrails/data.tf#L5)
- data source.google_tags_tag_key.containment (envs/gcp/guardrails/data.tf#L12)
- data source.google_tags_tag_value.containment_protected (envs/gcp/guardrails/data.tf#L19)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_containment_exempt_principals"></a> [containment\_exempt\_principals](#input\_containment\_exempt\_principals) | Break-glass principals exempt from the admin-containment deny policy, as IAM v2 principal identifiers (e.g. principalSet://goog/group/break-glass@acme.com). Empty (default) = principalSet://goog/group/<gcp.break\_glass\_group> from config. Placeholder values (REPLACE-ME, your-domain, example.com, .invalid) are rejected. | `list(string)` | `[]` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | The domain name of the organization (e.g. acme.com); the org node the deny policies attach to is resolved from it. Null = org.domain from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_enable_admin_containment"></a> [enable\_admin\_containment](#input\_enable\_admin\_containment) | Create the admin-containment deny policy. Org-wide, it blocks sink update/delete, exclusion changes, log-bucket delete and VPC-SC perimeter mutation. Scoped by the containment/protected tag to the audit store, it blocks bucket delete/IAM change/untag, object delete, key-version destroy/disable and key IAM change. containment\_exempt\_principals (break-glass) are exempt. Null (default) = gcp.admin\_containment from config, else ON whenever an environment is\_production, as in gcp-organization (which creates and binds the tag). Needs a break-glass principal. | `bool` | `null` | no |
| <a name="input_enable_principal_access_boundary"></a> [enable\_principal\_access\_boundary](#input\_enable\_principal\_access\_boundary) | Also deny update, delete and unbind of the automation principal access boundary to all but break-glass. Null (default) = gcp.principal\_access\_boundary from config/landing-zone.yaml, the key gcp-organization reads for the boundary itself, else false. Set the config key rather than this variable so the two cannot drift. | `bool` | `null` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Environment keys with is\_production (default false). A production environment turns admin containment on. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin); other attributes are ignored here. | <pre>map(object({<br/>    is_production = optional(bool, false)<br/>  }))</pre> | `null` | no |
| <a name="input_iam_deny_policies"></a> [iam\_deny\_policies](#input\_iam\_deny\_policies) | Extra IAM deny policies at the org node, applied next to the containment policy: a coarse, allow-independent backstop blocking specific permissions for specific principals regardless of roles (deny before allow). Default [] = none. | <pre>list(object({<br/>    name         = string<br/>    display_name = optional(string)<br/>    rules = list(object({<br/>      description           = optional(string)<br/>      denied_principals     = list(string)<br/>      denied_permissions    = list(string)<br/>      exception_principals  = optional(list(string), [])<br/>      exception_permissions = optional(list(string), [])<br/>      denial_condition = optional(object({<br/>        expression  = string<br/>        title       = optional(string)<br/>        description = optional(string)<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |
| <a name="input_landing_zone_config_path"></a> [landing\_zone\_config\_path](#input\_landing\_zone\_config\_path) | Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; "" disables the lookup. Read only if the file exists; explicit variables win over its values. | `string` | `null` | no |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Landing-zone prefix, used only for the provider default labels. Null = org.prefix from config/landing-zone.yaml. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_containment_enabled"></a> [admin\_containment\_enabled](#output\_admin\_containment\_enabled) | Whether the admin-containment deny policy is on (explicit enable\_admin\_containment, else gcp.admin\_containment, else on when any environment is\_production). |
| <a name="output_admin_containment_rules"></a> [admin\_containment\_rules](#output\_admin\_containment\_rules) | Rules of the admin-containment deny policy (empty when containment is off). |
| <a name="output_deny_policy_ids"></a> [deny\_policy\_ids](#output\_deny\_policy\_ids) | Map of deny-policy name to resource ID. |
| <a name="output_deny_policy_names"></a> [deny\_policy\_names](#output\_deny\_policy\_names) | Names of the IAM deny policies applied at the org node. |
| <a name="output_deny_policy_specs"></a> [deny\_policy\_specs](#output\_deny\_policy\_specs) | Map of deny-policy ID => gcloud policy-file JSON, for the break-glass path only (docs/runbooks/break-glass.md). Routine changes go through a security-team apply of this workspace. |
<!-- END_TF_DOCS -->
