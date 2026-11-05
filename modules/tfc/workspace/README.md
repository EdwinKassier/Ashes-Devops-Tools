# tfc/workspace

Creates one Terraform Cloud workspace and its variables. Used by the `tfc-admin`
root to declare the whole workspace layer (names, working directories, VCS wiring,
variables) as versioned, reviewable code instead of hand-created UI state (audit
C3). Foundational workspaces default to manual apply (`auto_apply = false`).

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name = 
	organization = 
	working_directory = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_tfe"></a> [tfe](#requirement\_tfe) | ~> 0.60 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_tfe"></a> [tfe](#provider\_tfe) | 0.83.0 |



## Resources

The following resources are created:


- resource.tfe_notification_configuration.this (modules/tfc/workspace/main.tf#L48)
- resource.tfe_variable.this (modules/tfc/workspace/main.tf#L34)
- resource.tfe_workspace.this (modules/tfc/workspace/main.tf#L6)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Workspace name, e.g. gcp-organization or aws-workload-prod. | `string` | n/a | yes |
| <a name="input_organization"></a> [organization](#input\_organization) | Terraform Cloud organization that owns the workspace. | `string` | n/a | yes |
| <a name="input_working_directory"></a> [working\_directory](#input\_working\_directory) | Repo-relative directory this workspace plans/applies from, e.g. envs/gcp/organization. | `string` | n/a | yes |
| <a name="input_auto_apply"></a> [auto\_apply](#input\_auto\_apply) | Apply automatically after a successful plan. Default false: foundational workspaces require manual apply approval. | `bool` | `false` | no |
| <a name="input_description"></a> [description](#input\_description) | Human-readable description of what the workspace deploys. | `string` | `null` | no |
| <a name="input_execution_mode"></a> [execution\_mode](#input\_execution\_mode) | TFC execution mode. 'remote' (default) runs plans/applies in TFC; 'agent'/'local' for special cases. | `string` | `"remote"` | no |
| <a name="input_file_triggers_enabled"></a> [file\_triggers\_enabled](#input\_file\_triggers\_enabled) | Trigger runs only when files under working\_directory (or trigger\_patterns) change. | `bool` | `true` | no |
| <a name="input_notifications"></a> [notifications](#input\_notifications) | Run notifications for this workspace, keyed by name. Default empty. Use this to<br/>alert on failed control-plane runs (audit M-ops): a failed apply on a<br/>foundational workspace is a control-plane event that should page someone.<br/><br/>Per entry:<br/>  destination\_type  generic \| slack \| microsoft-teams \| email.<br/>  url               webhook URL (required for non-email destinations).<br/>  token             optional HMAC token for a generic webhook.<br/>  email\_user\_ids    TFC user IDs to email (email destination only).<br/>  triggers          run events to notify on; default is a failed run plus a<br/>                    run that needs attention (manual apply waiting).<br/>  enabled           default true. | <pre>map(object({<br/>    destination_type = string<br/>    url              = optional(string)<br/>    token            = optional(string)<br/>    email_user_ids   = optional(list(string), [])<br/>    triggers         = optional(list(string), ["run:errored", "run:needs_attention"])<br/>    enabled          = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_queue_all_runs"></a> [queue\_all\_runs](#input\_queue\_all\_runs) | Queue a run as soon as the workspace is created. Default false so the first apply is deliberate. | `bool` | `false` | no |
| <a name="input_tag_names"></a> [tag\_names](#input\_tag\_names) | TFC workspace tags (e.g. cloud:gcp, layer:control-plane). | `list(string)` | `[]` | no |
| <a name="input_terraform_version"></a> [terraform\_version](#input\_terraform\_version) | Terraform version constraint for the workspace, e.g. ~> 1.9. Null uses the TFC default. | `string` | `null` | no |
| <a name="input_trigger_patterns"></a> [trigger\_patterns](#input\_trigger\_patterns) | Glob patterns that trigger a run (in addition to working\_directory). Empty = working\_directory only. | `list(string)` | `[]` | no |
| <a name="input_variables"></a> [variables](#input\_variables) | Workspace variables keyed by name: {value, category (terraform\|env), hcl?, sensitive?, description?}. | <pre>map(object({<br/>    value       = string<br/>    category    = string<br/>    hcl         = optional(bool, false)<br/>    sensitive   = optional(bool, false)<br/>    description = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_vcs_repo"></a> [vcs\_repo](#input\_vcs\_repo) | Optional VCS connection: {identifier = "org/repo", branch = "main", oauth\_token\_id = "ot-..."}. Null = API/CLI-driven workspace. | <pre>object({<br/>    identifier     = string<br/>    branch         = optional(string, "main")<br/>    oauth_token_id = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The workspace ID (ws-...). |
| <a name="output_name"></a> [name](#output\_name) | The workspace name. |
| <a name="output_notification_ids"></a> [notification\_ids](#output\_notification\_ids) | Map of notification name to its configuration ID. |
<!-- END_TF_DOCS -->
