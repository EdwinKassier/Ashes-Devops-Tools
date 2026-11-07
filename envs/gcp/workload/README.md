# Apps Root

`envs/gcp/workload` is the single deployable root for application environments. Set `TF_WORKSPACE=gcp-workload-<env>` and provide the matching `environment` tfvars value to deploy `dev`, `uat`, `prod`, or any new environment added to `envs/gcp/organization`.

The root resolves `config/landing-zone.yaml`, presets and the upstream stage contracts, then calls one module: [`modules/gcp/stages/environment`](../../../modules/gcp/stages/environment/), which composes the spoke network, budget, service teams, VM operations, the SaaS secret bridge, app services and public ingress. `moved.tf` carries the state moves into `module.environment`.

Example:

```bash
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload init
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload plan -var-file=../../../examples/dev.tfvars.example
```

By default this root reads organization outputs from the Terraform Cloud workspace named `organization`.
