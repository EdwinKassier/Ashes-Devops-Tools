# artifact_registry

Provisions Google Artifact Registry repositories for storing and managing container images and language packages. Supports Docker, Python (PyPI), npm, Maven, Go, and Apt formats with optional CMEK encryption and VPC Service Controls integration.

**When to use:** use this module whenever a workload needs a private registry for container images or language packages. Pair with `modules/governance/kms` to supply a CMEK key for compliance environments.

<!-- BEGIN_TF_DOCS -->
Artifact Registry Module
Creates repositories for storing container images and language packages.
Supports Docker, Python, npm, Maven, Go, and Apt formats.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	
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


- resource.google_artifact_registry_repository.repo (modules/artifact-registry/main.tf#L18)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the Artifact Registry repositories will be created | `string` | n/a | yes |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Customer-managed KMS key name used to encrypt repository contents. Omit for Google-managed encryption. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all repositories | `map(string)` | <pre>{<br/>  "managed-by": "terraform"<br/>}</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | The region where the Artifact Registry repositories will be created | `string` | `"us-central1"` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Map of repository configurations to create. Valid format values: DOCKER, MAVEN, NPM, PYTHON, APT, YUM, GOOGET, KFP, GENERIC. | <pre>map(object({<br/>    description               = string<br/>    format                    = optional(string, "DOCKER")<br/>    immutable_tags            = optional(bool, true)<br/>    allow_snapshot_overwrites = optional(bool, false)<br/>    version_policy            = optional(string, "VERSION_POLICY_UNSPECIFIED")<br/>  }))</pre> | <pre>{<br/>  "ashes-django-repo": {<br/>    "description": "Artifact registry for django images"<br/>  },<br/>  "ashes-express-repo": {<br/>    "description": "Artifact registry for express images"<br/>  },<br/>  "ashes-fastapi-repo": {<br/>    "description": "Artifact registry for fastapi images"<br/>  },<br/>  "ashes-flask-repo": {<br/>    "description": "Artifact registry for flask images"<br/>  },<br/>  "ashes-hermes-repo": {<br/>    "description": "Artifact registry for hermes images"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_repository_ids"></a> [repository\_ids](#output\_repository\_ids) | Map of repository names to their IDs |
| <a name="output_repository_names"></a> [repository\_names](#output\_repository\_names) | Map of repository names to their full resource names |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository names to their package-registry URLs, built per format (docker/maven/npm/python). Formats without a registry host (APT/YUM/GOOGET/KFP/GENERIC) are omitted. |
<!-- END_TF_DOCS -->