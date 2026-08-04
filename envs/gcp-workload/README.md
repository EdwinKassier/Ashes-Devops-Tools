# Apps Root

`envs/gcp-workload` is the single deployable root for application environments. Set `TF_WORKSPACE=gcp-workload-<env>` and provide the matching `environment` tfvars value to deploy `dev`, `uat`, `prod`, or any new environment added to `envs/gcp-organization`.

Example:

```bash
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp-workload init
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp-workload plan -var-file=../../examples/dev.tfvars
```

By default this root reads organization outputs from the Terraform Cloud workspace named `organization`.
