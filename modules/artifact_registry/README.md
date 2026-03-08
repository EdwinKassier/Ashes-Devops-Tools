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
	kms_key_name = 
	project_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_artifact_registry_repository.repo (modules/artifact_registry/main.tf#L7)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Customer-managed KMS key name used to encrypt repository contents | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID where the Artifact Registry repositories will be created | `string` | n/a | yes |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all repositories | `map(string)` | <pre>{<br/>  "managed-by": "terraform"<br/>}</pre> | no |
| <a name="input_region"></a> [region](#input\_region) | The region where the Artifact Registry repositories will be created | `string` | `"us-central1"` | no |
| <a name="input_repositories"></a> [repositories](#input\_repositories) | Map of repository configurations to create | <pre>map(object({<br/>    description    = string<br/>    format         = optional(string, "DOCKER")<br/>    immutable_tags = optional(bool, true)<br/>  }))</pre> | <pre>{<br/>  "ashes-django-repo": {<br/>    "description": "Artifact registry for django images"<br/>  },<br/>  "ashes-express-repo": {<br/>    "description": "Artifact registry for express images"<br/>  },<br/>  "ashes-fastapi-repo": {<br/>    "description": "Artifact registry for fastapi images"<br/>  },<br/>  "ashes-flask-repo": {<br/>    "description": "Artifact registry for flask images"<br/>  },<br/>  "ashes-hermes-repo": {<br/>    "description": "Artifact registry for hermes images"<br/>  }<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_repository_ids"></a> [repository\_ids](#output\_repository\_ids) | Map of repository names to their IDs |
| <a name="output_repository_names"></a> [repository\_names](#output\_repository\_names) | Map of repository names to their full resource names |
| <a name="output_repository_urls"></a> [repository\_urls](#output\_repository\_urls) | Map of repository names to their Docker registry URLs |
<!-- END_TF_DOCS -->