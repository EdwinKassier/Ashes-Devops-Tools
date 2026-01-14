<!-- BEGIN_TF_DOCS -->


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


- resource.google_storage_bucket.logs (modules/cloud_storage/main.tf#L2)
- resource.google_storage_bucket.looker_data_backup (modules/cloud_storage/main.tf#L67)
- resource.google_storage_bucket.twitter_data_lake (modules/cloud_storage/main.tf#L33)
- resource.google_storage_bucket.twitter_dataflow_meta (modules/cloud_storage/main.tf#L50)
- resource.google_storage_bucket_iam_binding.log_writer (modules/cloud_storage/main.tf#L24)
- resource.google_storage_bucket_iam_binding.private (modules/cloud_storage/main.tf#L85)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project | `string` | n/a | yes |
| <a name="input_allowed_members"></a> [allowed\_members](#input\_allowed\_members) | List of members with read access to the buckets (e.g., ['user:user@example.com', 'group:admins@example.com']) | `list(string)` | `[]` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | The name of the KMS key to use for encryption | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain logs in the logging bucket | `number` | `90` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | `"us-central1"` | no |

## Outputs

No outputs.

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