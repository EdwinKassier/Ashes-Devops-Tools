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

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |



## Resources

The following resources are created:


- resource.google_artifact_registry_repository.repo (modules/artifact_registry/main.tf#L7)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
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

## Security Considerations

- Ensure all sensitive variables are marked as `sensitive = true`
- Use GCP Secret Manager for storing secrets
- Follow the principle of least privilege for IAM roles
- Enable audit logging for compliance

## Contributing

Contributions are welcome! Please read the [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

This module is licensed under the MIT License. See [LICENSE](../../LICENSE) for details.
<!-- END_TF_DOCS -->