# tfc/workspace

Creates one Terraform Cloud workspace with its variables, settings
(`tfe_workspace_settings`: execution mode, explicit remote-state consumers,
`global_remote_state = false`), variable-set attachments and notifications. Used by
the `tfc-admin` root to declare the workspace layer as versioned, reviewable code
instead of hand-created UI state (audit C3). Foundational workspaces default to
manual apply (`auto_apply = false`); health assessments default on; callers turn
off `speculative_enabled` for the control plane and pass `trigger_patterns` that
cover the module domains the root consumes. Set `manage_settings = false` when the
caller wires remote-state consumers between sibling workspaces itself.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_tfe"></a> [tfe](#requirement\_tfe) | >= 0.83.0, < 1.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_tfe"></a> [tfe](#provider\_tfe) | 0.83.0 |



## Resources

The following resources are created:


- resource.tfe_notification_configuration.this (modules/tfc/workspace/main.tf#L90)
- resource.tfe_variable.this (modules/tfc/workspace/main.tf#L65)
- resource.tfe_workspace.this (modules/tfc/workspace/main.tf#L7)
- resource.tfe_workspace_settings.this (modules/tfc/workspace/main.tf#L52)
- resource.tfe_workspace_variable_set.this (modules/tfc/workspace/main.tf#L81)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Workspace name, e.g. gcp-organization or aws-workload-prod. | `string` | n/a | yes |
| <a name="input_organization"></a> [organization](#input\_organization) | Terraform Cloud organization that owns the workspace. | `string` | n/a | yes |
| <a name="input_working_directory"></a> [working\_directory](#input\_working\_directory) | Repo-relative directory this workspace plans/applies from, e.g. envs/gcp/organization. | `string` | n/a | yes |
| <a name="input_agent_pool_id"></a> [agent\_pool\_id](#input\_agent\_pool\_id) | Agent pool ID (apool-...) used when execution\_mode = agent. Ignored otherwise. | `string` | `null` | no |
| <a name="input_allow_destroy_plan"></a> [allow\_destroy\_plan](#input\_allow\_destroy\_plan) | Allow destroy plans to be queued from the UI/API. Set false for control-plane workspaces. | `bool` | `true` | no |
| <a name="input_assessments_enabled"></a> [assessments\_enabled](#input\_assessments\_enabled) | Enable health assessments (native drift detection and continuous validation). Requires an HCP Terraform tier that includes health assessments. | `bool` | `true` | no |
| <a name="input_auto_apply"></a> [auto\_apply](#input\_auto\_apply) | Apply automatically after a successful plan. Default false: foundational workspaces require manual apply approval. | `bool` | `false` | no |
| <a name="input_auto_apply_run_trigger"></a> [auto\_apply\_run\_trigger](#input\_auto\_apply\_run\_trigger) | Apply automatically after a successful plan that a run trigger (an upstream workspace's apply) queued. Independent of auto\_apply. Default false. | `bool` | `false` | no |
| <a name="input_description"></a> [description](#input\_description) | Human-readable description of what the workspace deploys. | `string` | `null` | no |
| <a name="input_execution_mode"></a> [execution\_mode](#input\_execution\_mode) | TFC execution mode. 'remote' (default) runs plans/applies in TFC; 'agent'/'local' for special cases. | `string` | `"remote"` | no |
| <a name="input_file_triggers_enabled"></a> [file\_triggers\_enabled](#input\_file\_triggers\_enabled) | Trigger runs only when files under working\_directory (or trigger\_patterns) change. | `bool` | `true` | no |
| <a name="input_global_remote_state"></a> [global\_remote\_state](#input\_global\_remote\_state) | Share this workspace's state with EVERY workspace in the organization. Default false: share only with remote\_state\_consumer\_ids. | `bool` | `false` | no |
| <a name="input_manage_settings"></a> [manage\_settings](#input\_manage\_settings) | Create the tfe\_workspace\_settings resource (execution mode, agent pool, remote-state sharing). Set false when the caller manages settings itself (e.g. to wire remote-state consumers between sibling workspaces). | `bool` | `true` | no |
| <a name="input_notifications"></a> [notifications](#input\_notifications) | Run notifications for this workspace, keyed by name. Default empty. Use this to<br/>alert on failed control-plane runs: a failed apply on a<br/>foundational workspace is a control-plane event that should page someone.<br/><br/>Per entry:<br/>  destination\_type  generic \| slack \| microsoft-teams \| email.<br/>  url               webhook URL (required for non-email destinations).<br/>  token             optional HMAC token for a generic webhook.<br/>  email\_user\_ids    TFC user IDs to email (email destination only).<br/>  triggers          run events to notify on; default is a failed run plus a<br/>                    run that needs attention (manual apply waiting). Health<br/>                    assessment events assessment:drifted, assessment:check\_failure<br/>                    and assessment:failed are also accepted.<br/>  enabled           default true. | <pre>map(object({<br/>    destination_type = string<br/>    url              = optional(string)<br/>    token            = optional(string)<br/>    email_user_ids   = optional(list(string), [])<br/>    triggers         = optional(list(string), ["run:errored", "run:needs_attention"])<br/>    enabled          = optional(bool, true)<br/>  }))</pre> | `{}` | no |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | TFC project (prj-...) to place the workspace in. Null = the organization's default project. | `string` | `null` | no |
| <a name="input_queue_all_runs"></a> [queue\_all\_runs](#input\_queue\_all\_runs) | Queue a run as soon as the workspace is created. Default false so the first apply is deliberate. | `bool` | `false` | no |
| <a name="input_remote_state_consumer_ids"></a> [remote\_state\_consumer\_ids](#input\_remote\_state\_consumer\_ids) | Workspace IDs (ws-...) allowed to read this workspace's state via terraform\_remote\_state / tfe\_outputs. Only used when global\_remote\_state = false. | `set(string)` | `[]` | no |
| <a name="input_speculative_enabled"></a> [speculative\_enabled](#input\_speculative\_enabled) | Allow automatic speculative plans on pull requests. Set false for control-plane workspaces so an untrusted PR cannot obtain a plan run with privileged credentials. | `bool` | `true` | no |
| <a name="input_tag_names"></a> [tag\_names](#input\_tag\_names) | TFC workspace tags (e.g. cloud:gcp, layer:control-plane). | `list(string)` | `[]` | no |
| <a name="input_terraform_version"></a> [terraform\_version](#input\_terraform\_version) | Terraform version for the workspace: an exact release such as 1.17.1 (envs/tfc-admin pins one) or a constraint. Null uses the TFC default. | `string` | `null` | no |
| <a name="input_trigger_patterns"></a> [trigger\_patterns](#input\_trigger\_patterns) | Glob patterns that trigger a run. When non-empty they REPLACE the working\_directory default, so include "<working\_directory>/**" plus every module path the root consumes (e.g. modules/gcp/**). Empty = working\_directory only. | `list(string)` | `[]` | no |
| <a name="input_variable_set_ids"></a> [variable\_set\_ids](#input\_variable\_set\_ids) | Variable sets to attach to this workspace, keyed by a stable label (the label keeps for\_each plan-known while the set ID is unknown): {label = "varset-..."}. | `map(string)` | `{}` | no |
| <a name="input_variables"></a> [variables](#input\_variables) | Workspace variables keyed by name: {value, category (terraform\|env), hcl?, sensitive?, description?, version?}. Sensitive values are written write-only (never stored in state); increment `version` to rotate one. | <pre>map(object({<br/>    value       = string<br/>    category    = string<br/>    hcl         = optional(bool, false)<br/>    sensitive   = optional(bool, false)<br/>    description = optional(string)<br/>    version     = optional(number, 1)<br/>  }))</pre> | `{}` | no |
| <a name="input_vcs_repo"></a> [vcs\_repo](#input\_vcs\_repo) | Optional VCS connection: {identifier = "org/repo", branch = "main", oauth\_token\_id = "ot-..."} or github\_app\_installation\_id instead of oauth\_token\_id. Null = API/CLI-driven workspace. | <pre>object({<br/>    identifier                 = string<br/>    branch                     = optional(string, "main")<br/>    oauth_token_id             = optional(string)<br/>    github_app_installation_id = optional(string)<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_allow_destroy_plan"></a> [allow\_destroy\_plan](#output\_allow\_destroy\_plan) | Whether destroy plans may be queued from the UI/API. |
| <a name="output_auto_apply"></a> [auto\_apply](#output\_auto\_apply) | Whether a successful plan applies without confirmation. |
| <a name="output_auto_apply_run_trigger"></a> [auto\_apply\_run\_trigger](#output\_auto\_apply\_run\_trigger) | Whether a successful plan queued by a run trigger applies without confirmation. |
| <a name="output_id"></a> [id](#output\_id) | The workspace ID (ws-...). |
| <a name="output_name"></a> [name](#output\_name) | The workspace name. |
| <a name="output_notification_ids"></a> [notification\_ids](#output\_notification\_ids) | Map of notification name to its configuration ID. |
| <a name="output_queue_all_runs"></a> [queue\_all\_runs](#output\_queue\_all\_runs) | Whether the workspace queues a run as soon as it is created. |
| <a name="output_remote_state_consumer_ids"></a> [remote\_state\_consumer\_ids](#output\_remote\_state\_consumer\_ids) | Workspace IDs allowed to read this workspace's state as managed by this module (empty when global\_remote\_state = true or manage\_settings = false). |
| <a name="output_speculative_enabled"></a> [speculative\_enabled](#output\_speculative\_enabled) | Whether automatic speculative (PR) plans are allowed. |
| <a name="output_tag_names"></a> [tag\_names](#output\_tag\_names) | Workspace tags (sorted). |
| <a name="output_terraform_version"></a> [terraform\_version](#output\_terraform\_version) | Terraform version the workspace runs (null = the TFC default). |
| <a name="output_trigger_patterns"></a> [trigger\_patterns](#output\_trigger\_patterns) | Trigger patterns configured on the workspace. |
| <a name="output_variable_keys"></a> [variable\_keys](#output\_variable\_keys) | Sorted keys of the variables set directly on the workspace (values omitted; some are sensitive). |
| <a name="output_variable_set_labels"></a> [variable\_set\_labels](#output\_variable\_set\_labels) | Labels of the variable sets attached to this workspace. |
| <a name="output_variable_values"></a> [variable\_values](#output\_variable\_values) | Values of the NON-sensitive variables set directly on the workspace, keyed by name (sensitive ones are omitted). |
| <a name="output_working_directory"></a> [working\_directory](#output\_working\_directory) | Working directory (root) the workspace runs in. |
<!-- END_TF_DOCS -->

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
