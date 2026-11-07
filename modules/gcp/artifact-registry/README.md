# artifact_registry

Provisions Google Artifact Registry repositories for storing and managing container images and language packages. Supports Docker, Python (PyPI), npm, Maven, Go, and Apt formats with optional CMEK encryption and VPC Service Controls integration.

**When to use:** use this module whenever a workload needs a private registry for container images or language packages. Pair with `modules/gcp/governance/kms` to supply a CMEK key for compliance environments.

<!-- BEGIN_TF_DOCS -->
Artifact Registry Module
Creates repositories for storing container images and language packages.
Supports Docker, Python, npm, Maven, Go, and Apt formats.

Vulnerability scanning (enable\_vulnerability\_scanning, default on) enables the
Container Scanning API and sets DOCKER repositories to scan automatically on push
(vulnerability\_scanning\_config = INHERITED, following the project setting).

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id =
	region =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.10.0 |



## Resources

The following resources are created:


- resource.google_artifact_registry_repository.repo (modules/gcp/artifact-registry/main.tf#L32)
- resource.google_project_service.container_scanning (modules/gcp/artifact-registry/main.tf#L24)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the Artifact Registry repositories will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The region where the Artifact Registry repositories will be created | `string` | n/a | yes |
| <a name="input_enable_container_scanning_api"></a> [enable\_container\_scanning\_api](#input\_enable\_container\_scanning\_api) | Enable containerscanning.googleapis.com on project\_id when enable\_vulnerability\_scanning is true. Set false when the caller already manages project APIs (disable\_on\_destroy is false either way). | `bool` | `true` | no |
| <a name="input_enable_vulnerability_scanning"></a> [enable\_vulnerability\_scanning](#input\_enable\_vulnerability\_scanning) | Scan DOCKER images automatically on push (Artifact Analysis). Sets each DOCKER repository's vulnerability\_scanning\_config to INHERITED (DISABLED when false) and, with enable\_container\_scanning\_api, enables containerscanning.googleapis.com. Scanning is billed per image. | `bool` | `true` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Customer-managed KMS key name used to encrypt repository contents. Omit for Google-managed encryption. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all repositories | `map(string)` | <pre>{<br/>  "managed-by": "terraform"<br/>}</pre> | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Map of repository configurations to create. Valid format values: DOCKER, MAVEN,<br/>NPM, PYTHON, APT, YUM, GOOGET, KFP, GENERIC.<br/>`cleanup_policies` is keyed by policy id; each has `action` (DELETE or KEEP) and<br/>either a `condition` (tag\_state TAGGED/UNTAGGED/ANY, tag/version/package name<br/>prefixes, older\_than/newer\_than durations such as "2592000s") or<br/>`most_recent_versions` (keep\_count). `cleanup_policy_dry_run` (default false)<br/>only logs what would be deleted. | <pre>map(object({<br/>    description               = string<br/>    format                    = optional(string, "DOCKER")<br/>    immutable_tags            = optional(bool, true)<br/>    allow_snapshot_overwrites = optional(bool, false)<br/>    version_policy            = optional(string, "VERSION_POLICY_UNSPECIFIED")<br/>    cleanup_policy_dry_run    = optional(bool, false)<br/>    cleanup_policies = optional(map(object({<br/>      action = string<br/>      condition = optional(object({<br/>        tag_state             = optional(string)<br/>        tag_prefixes          = optional(list(string))<br/>        version_name_prefixes = optional(list(string))<br/>        package_name_prefixes = optional(list(string))<br/>        older_than            = optional(string)<br/>        newer_than            = optional(string)<br/>      }))<br/>      most_recent_versions = optional(object({<br/>        package_name_prefixes = optional(list(string))<br/>        keep_count            = optional(number)<br/>      }))<br/>    })), {})<br/>  }))</pre> | <pre>{<br/>  "ashes-django-repo": {<br/>    "description": "Artifact registry for django images"<br/>  },<br/>  "ashes-express-repo": {<br/>    "description": "Artifact registry for express images"<br/>  },<br/>  "ashes-fastapi-repo": {<br/>    "description": "Artifact registry for fastapi images"<br/>  },<br/>  "ashes-flask-repo": {<br/>    "description": "Artifact registry for flask images"<br/>  },<br/>  "ashes-hermes-repo": {<br/>    "description": "Artifact registry for hermes images"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_repository_ids"></a> [repository\_ids](#output\_repository\_ids) | Map of repository names to their IDs |
| <a name="output_repository_names"></a> [repository\_names](#output\_repository\_names) | Map of repository names to their full resource names |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository names to their package-registry URLs, built per format (docker/maven/npm/python). Formats without a registry host (APT/YUM/GOOGET/KFP/GENERIC) are omitted. |
| <a name="output_vulnerability_scanning_enabled"></a> [vulnerability\_scanning\_enabled](#output\_vulnerability\_scanning\_enabled) | Whether DOCKER repositories are configured to scan pushed images (enable\_vulnerability\_scanning). |
<!-- END_TF_DOCS -->
