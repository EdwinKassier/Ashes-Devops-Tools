# Ashes DevOps Tools Documentation Index

## Start Here

- [README](../README.md): repo overview, supported roots, and release model
- [Quick Start](guides/QUICK_START.md): local setup and first validation run
- [Architecture](architecture/ARCHITECTURE.md): control plane, app root, and CI/CD flow
- [Troubleshooting](guides/TROUBLESHOOTING.md): common local and workflow failures

## Core Concepts

- `envs/organization` is the control-plane root.
- `envs/apps` is the only deployable application-environment root.
- Terraform Cloud owns live state and apply runs.
- GitHub Actions validates code and publishes release metadata.

## Common Tasks

### Initialize the roots

```bash
terraform -chdir=envs/organization init
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps init
```

### Run fast local checks

```bash
make fmt-check
make docs-check
make security
```

### Run deeper local checks

```bash
make validate-all
make lint
```

`make validate-all` requires provider-registry access. `make lint` also requires a working local TFLint Google ruleset plugin.

### Plan changes

```bash
make plan-organization
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
```

## Reference Files

- [Makefile](../Makefile): local operator commands
- [.terraform-docs.yml](../.terraform-docs.yml): docs generation config
- [.tflint.hcl](../.tflint.hcl): TFLint config
- [.tfsec.yml](../.tfsec.yml): TFSec config
- [terraform-plan.yml](../.github/workflows/terraform-plan.yml): PR validation workflow
- [terraform-apply.yml](../.github/workflows/terraform-apply.yml): release-metadata workflow

## External Resources

- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Google Cloud Best Practices](https://cloud.google.com/docs/enterprise/best-practices-for-enterprise-organizations)
- [TFLint Rules](https://github.com/terraform-linters/tflint/tree/master/docs/rules)
- [TFSec Checks](https://aquasecurity.github.io/tfsec/)
