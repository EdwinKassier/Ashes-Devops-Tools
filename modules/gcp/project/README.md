# gcp/project

The single GCP **project primitive** of the landing zone. `stages/bootstrap`,
`stages/projects` and `stages/workload` all create projects through it, so the
project baseline is defined once (audit Modularity-H: previously three different
code paths, one of them force-enabling `container.googleapis.com`).

**Baseline (not configurable):** `auto_create_network = false`; APIs enabled with
`disable_on_destroy = false`. **Defaulted:** `deletion_policy = "PREVENT"`.

**No naming scheme:** `project_id` and `name` are used verbatim — prefixes,
environment keys and random suffixes are the calling stage's job.

**Optional features:** Shared VPC service-project attachment
(`shared_vpc_host_project_id`), additive IAM (`iam`, role => members), Essential
Contacts, a deletion lien (`lien_reason`) and tag bindings (`tag_bindings`).

**Not in scope:** default-service-account deprivilege at the org level is the
`iam.automaticIamGrantsForDefaultServiceAccounts` org policy
(`governance/org-policy`); budgets live in `governance/billing`.

```hcl
module "project" {
  source = "../../modules/gcp/project"

  project_id      = "acme-dev-app-1a2b"
  parent          = "folders/123456789012"
  billing_account = "ABCDEF-123456-ABCDEF"
  services        = ["compute.googleapis.com"]

  shared_vpc_host_project_id = "acme-dev-host-1a2b"
  iam = {
    "roles/logging.viewer" = ["group:app-team@example.com"]
  }
}
```

See [`examples/basic`](examples/basic/main.tf).

<!-- BEGIN_TF_DOCS -->
# gcp/project

The single GCP **project primitive** for the landing zone (Cloud Foundation
Fabric `project`-module style). Every stage that creates a project —
`stages/bootstrap` (admin project), `stages/projects` (hub / DNS / env host
projects) and `stages/workload` (service-team projects) — calls this module,
so the project baseline (no default network, `PREVENT` deletion policy, APIs
left enabled on destroy) is defined in exactly one place.

The module has **no naming scheme**: `project_id` and `name` are passed in
verbatim. Prefixes, environment keys and random suffixes belong to the calling
stage.

Optional features (all off by default): Shared VPC service-project attachment,
additive IAM, Essential Contacts, a deletion lien and resource-manager tag
bindings.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	parent =
	project_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |



## Resources

The following resources are created:


- resource.google_compute_shared_vpc_service_project.this (modules/gcp/project/main.tf#L70)
- resource.google_essential_contacts_contact.this (modules/gcp/project/main.tf#L94)
- resource.google_project.this (modules/gcp/project/main.tf#L36)
- resource.google_project_iam_member.this (modules/gcp/project/main.tf#L84)
- resource.google_project_service.this (modules/gcp/project/main.tf#L56)
- resource.google_resource_manager_lien.this (modules/gcp/project/main.tf#L107)
- resource.google_tags_tag_binding.this (modules/gcp/project/main.tf#L118)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_parent"></a> [parent](#input\_parent) | Parent resource the project is created under: "folders/<numeric id>" or "organizations/<numeric id>". | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Globally unique project ID, used verbatim (this module applies no prefix or suffix). 6-30 chars: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen. | `string` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account ID (XXXXXX-XXXXXX-XXXXXX) to link. Null leaves the project without billing (most APIs then cannot be enabled). | `string` | `null` | no |
| <a name="input_deletion_policy"></a> [deletion\_policy](#input\_deletion\_policy) | Project deletion policy: PREVENT (default — a destroy plan fails), ABANDON (remove from state, keep the project) or DELETE. | `string` | `"PREVENT"` | no |
| <a name="input_essential_contacts"></a> [essential\_contacts](#input\_essential\_contacts) | Essential Contacts: map of email => list of notification categories (ALL, SUSPENSION, SECURITY, TECHNICAL, BILLING, LEGAL, PRODUCT\_UPDATES, TECHNICAL\_INCIDENTS). Requires essentialcontacts.googleapis.com on the project (or the org-level contacts API). | `map(list(string))` | `{}` | no |
| <a name="input_essential_contacts_language"></a> [essential\_contacts\_language](#input\_essential\_contacts\_language) | Language tag (BCP-47) for Essential Contacts notifications. | `string` | `"en"` | no |
| <a name="input_iam"></a> [iam](#input\_iam) | Additive project IAM: map of role => set of members ("user:", "group:", "serviceAccount:", "domain:", "principal:" or "principalSet:"). Uses google\_project\_iam\_member, so bindings managed elsewhere are never evicted. | `map(set(string))` | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the project (GCP label rules): keys start with a lowercase letter, then lowercase letters, digits, '\_' or '-' (max 63); values use the same charset (max 63, may be empty). International lowercase characters are allowed. No uppercase or spaces. | `map(string)` | `{}` | no |
| <a name="input_lien_reason"></a> [lien\_reason](#input\_lien\_reason) | When set, place a resourcemanager.projects.delete lien on the project with this reason (a second, API-level guard on top of deletion\_policy). Null = no lien. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Human-readable display name (4-30 chars). Defaults to project\_id when null. | `string` | `null` | no |
| <a name="input_services"></a> [services](#input\_services) | APIs to enable on the project (e.g. "compute.googleapis.com"). Enabled with disable\_on\_destroy = false, so removing one from this list only stops managing it. | `list(string)` | `[]` | no |
| <a name="input_shared_vpc_host_project_id"></a> [shared\_vpc\_host\_project\_id](#input\_shared\_vpc\_host\_project\_id) | When set, attach this project as a Shared VPC service project of the given host project. The host must already be a Shared VPC host and compute.googleapis.com must be in var.services. Null = no attachment. | `string` | `null` | no |
| <a name="input_tag_bindings"></a> [tag\_bindings](#input\_tag\_bindings) | Resource-manager tag bindings: map of arbitrary static key => tag value ID ("tagValues/<numeric id>"). Keys must be known at plan time. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_billing_account"></a> [billing\_account](#output\_billing\_account) | The billing account linked to the project (null if none). |
| <a name="output_id"></a> [id](#output\_id) | The project resource ID (projects/<project\_id>). |
| <a name="output_labels"></a> [labels](#output\_labels) | The labels applied to the project. |
| <a name="output_name"></a> [name](#output\_name) | The project display name. |
| <a name="output_number"></a> [number](#output\_number) | The numeric project number. |
| <a name="output_parent"></a> [parent](#output\_parent) | The parent the project was created under (folders/<id> or organizations/<id>). |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The project ID. Depends on API enablement, so consumers wait until var.services are live. |
| <a name="output_services"></a> [services](#output\_services) | Sorted list of APIs this module enables on the project. |
| <a name="output_shared_vpc_host_project_id"></a> [shared\_vpc\_host\_project\_id](#output\_shared\_vpc\_host\_project\_id) | The Shared VPC host project this project is attached to (null when not attached). |
<!-- END_TF_DOCS -->
