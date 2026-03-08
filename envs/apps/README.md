# Apps Root

`envs/apps` is the single deployable root for application environments. Set `TF_WORKSPACE=apps-<env>` and provide the matching `environment` tfvars value to deploy `dev`, `uat`, `prod`, or any new environment added to `envs/organization`.

Example:

```bash
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps init
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
```

By default this root reads organization outputs from the Terraform Cloud workspace named `organization`.
