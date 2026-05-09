# Ashes DevOps Tools Documentation Index

## Start Here

- [README](../README.md): repo overview, supported roots, and release model
- [Quick Start](guides/QUICK_START.md): local setup and first validation run
- [Architecture](architecture/ARCHITECTURE.md): control plane, app root, and CI/CD flow
- [Troubleshooting](guides/TROUBLESHOOTING.md): common local and workflow failures

## Core Concepts

- `envs/organization` is the control-plane root.
- `envs/apps` is the only deployable application-environment root.
- `modules/stages/saas-workload` composes Supabase + Vercel for per-environment SaaS deployments.
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

## Runbooks

- [Quick Start](guides/QUICK_START.md): bootstrap sequence, backend config, first apply
- [Add Environment](runbooks/add-environment.md): provision a new dev/staging/prod environment
- [Service Team Onboarding](runbooks/service-team-onboarding.md): create a service project with Shared VPC attachment
- [KMS Rotation](runbooks/kms-rotation.md): rotate CMEK keys automatically or manually
- [CIDR Expansion](runbooks/cidr-expansion.md): expand subnet ranges without downtime
- [Break Glass](runbooks/break-glass.md): emergency access when Workload Identity Federation fails

## SaaS Modules

- [Quick Start → Section 3a](guides/QUICK_START.md#3a-configure-supabase-and-vercel-provider-credentials): Supabase + Vercel token setup, Node.js requirement
- [Architecture → SaaS Modules](architecture/ARCHITECTURE.md#saas-modules): module descriptions and design decisions
- [Troubleshooting → Supabase errors](guides/TROUBLESHOOTING.md#supabase-module-errors): token errors, provisioner failures, vault safety guard
- Module READMEs: [`modules/supabase/environment`](../modules/supabase/environment/README.md) · [`modules/supabase/vault-secrets`](../modules/supabase/vault-secrets/README.md) · [`modules/vercel/project`](../modules/vercel/project/README.md) · [`modules/stages/saas-workload`](../modules/stages/saas-workload/README.md)

## Security & Governance

- [Security Policy](../SECURITY.md): vulnerability reporting, disclosure timeline, and security architecture
- [Changelog](../CHANGELOG.md): release notes, breaking changes, and migration guides
- [Branch Protection](guides/BRANCH_PROTECTION.md): recommended GitHub branch protection and tag ruleset settings

## Architecture

- [Network Topology](architecture/network-topology.md): hub-spoke VPC layout, VPC-SC perimeter, WIF OIDC flow
- [Architecture Overview](architecture/ARCHITECTURE.md): control plane, app root, and CI/CD flow

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
