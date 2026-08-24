# Ashes DevOps Tools Documentation Index

## Start Here

- [README](../README.md): repo overview, supported roots, and release model
- [CLAUDE.md](../CLAUDE.md): onboarding guide for AI agents — repo layout, module authoring rules, common gotchas
- [Quick Start](guides/QUICK_START.md): local setup and first validation run
- [Architecture](architecture/ARCHITECTURE.md): control plane, app root, and CI/CD flow
- [Troubleshooting](guides/TROUBLESHOOTING.md): common local and workflow failures

## Core Concepts

- `envs/gcp/organization` is the GCP control-plane root.
- `envs/gcp/workload` is the deployable GCP application-environment root.
- `envs/aws/*` are the AWS landing-zone roots (one root = one TFC workspace); `envs/saas` deploys Supabase and/or Vercel only.
- `modules/saas/stages/saas-workload` composes Supabase + Vercel for per-environment SaaS deployments.
- Cloud selection is which workspaces you apply, not a runtime flag — see [Provider Selection](architecture/provider-selection.md).
- Terraform Cloud owns live state and apply runs.
- GitHub Actions validates code and publishes release metadata.

## Common Tasks

### Initialize the roots

```bash
terraform -chdir=envs/gcp/organization init
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload init
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
make plan-gcp-organization
make plan-gcp-workload APP_ENV=dev APP_VARS=examples/dev.tfvars
```

## Runbooks

- [Quick Start](guides/QUICK_START.md): bootstrap sequence, backend config, first apply
- [Add Environment](runbooks/add-environment.md): provision a new dev/staging/prod environment
- [Service Team Onboarding](runbooks/service-team-onboarding.md): create a service project with Shared VPC attachment
- [KMS Rotation](runbooks/kms-rotation.md): rotate CMEK keys automatically or manually
- [CIDR Expansion](runbooks/cidr-expansion.md): expand subnet ranges without downtime
- [Break Glass](runbooks/break-glass.md): emergency access when Workload Identity Federation fails
- [GCP Workspace Rename](runbooks/gcp-workspace-rename.md): migrate live TFC workspaces to the `gcp-organization` / `gcp-workload-<env>` names
- [Provider Upgrades](guides/provider-upgrades.md): google/google-beta major-version compatibility posture and re-test procedure

## GCP Landing Zone

- [GCP Landing Zone](architecture/gcp-landing-zone.md): enterprise-foundations architecture — folder/project model, two-root layer map, Shared VPC hub-spoke topology, security services, foundation conformance checklist
- [Adding a Cloud](architecture/adding-a-cloud.md): the per-cloud-root contract (naming, one provider per root, credential-free remote state)
- [Provider Selection](architecture/provider-selection.md): any-combination cloud matrix, per-cloud-root model
- [Bootstrap](runbooks/bootstrap.md): phase-0 stand-up from zero state to a runnable `gcp-organization` workspace
- [Add Environment](runbooks/add-environment.md): provision a new dev/staging/prod environment (a `gcp-workload-<env>` workspace)
- [Service Team Onboarding](runbooks/service-team-onboarding.md): create a service project with Shared VPC attachment
- [KMS Rotation](runbooks/kms-rotation.md): rotate CMEK keys automatically or manually
- [CIDR Expansion](runbooks/cidr-expansion.md): expand subnet ranges without downtime
- [Break Glass](runbooks/break-glass.md): emergency access when Workload Identity Federation fails
- [Incident Response](runbooks/incident-response.md): quarantine and forensics flow via SCC + VPC-SC
- [Teardown](runbooks/teardown.md): reverse-order destroy, `prevent_destroy` and CMEK caveats
- [GCP Workspace Rename](runbooks/gcp-workspace-rename.md): migrate live TFC workspaces to the `gcp-organization` / `gcp-workload-<env>` names

## AWS Landing Zone

- [AWS Landing Zone](architecture/aws-landing-zone.md): multi-account SRA architecture — account/OU model, layer map, network/security topology, SRA conformance checklist
- [Adding a Cloud](architecture/adding-a-cloud.md): the per-cloud-root contract (naming, one provider per root, credential-free remote state)
- [Provider Selection](architecture/provider-selection.md): any-combination cloud matrix, per-cloud-root model, minimum AWS footprint
- [AWS Bootstrap](runbooks/aws-bootstrap.md): phase-0 stand-up from zero state to a runnable `aws-organization` workspace
- [AWS Add Account](runbooks/aws-add-account.md): add a new AWS account/environment to the org
- [AWS KMS Rotation](runbooks/aws-kms-rotation.md): automatic vs on-demand rotation, key replacement, baseline-key impact
- [AWS CIDR Expansion](runbooks/aws-cidr-expansion.md): IPAM allocation, secondary VPC CIDRs, TGW propagation
- [AWS Break Glass](runbooks/aws-break-glass.md): emergency access via the break-glass role
- [AWS Incident Response](runbooks/aws-incident-response.md): quarantine and forensics flow
- [AWS Teardown](runbooks/aws-teardown.md): reverse-order destroy, WORM/Vault Lock caveats

## SaaS Modules

- [Quick Start → Section 3a](guides/QUICK_START.md#3a-configure-supabase-and-vercel-provider-credentials): Supabase + Vercel token setup, Node.js requirement
- [Architecture → SaaS Modules](architecture/ARCHITECTURE.md#saas-modules): module descriptions and design decisions
- [Troubleshooting → Supabase errors](guides/TROUBLESHOOTING.md#supabase-module-errors): token errors, provisioner failures, vault safety guard
- Module READMEs: [`modules/supabase/environment`](../modules/supabase/environment/README.md) · [`modules/supabase/vault-secrets`](../modules/supabase/vault-secrets/README.md) · [`modules/vercel/project`](../modules/vercel/project/README.md) · [`modules/saas/stages/saas-workload`](../modules/saas/stages/saas-workload/README.md)

## Security & Governance

- [Security Policy](../SECURITY.md): vulnerability reporting, disclosure timeline, and security architecture
- [Changelog](../CHANGELOG.md): release notes, breaking changes, and migration guides
- [Branch Protection](guides/BRANCH_PROTECTION.md): recommended GitHub branch protection and tag ruleset settings

## Architecture

- [Network Topology](architecture/network-topology.md): hub-spoke VPC layout, VPC-SC perimeter, WIF OIDC flow
- [Architecture Overview](architecture/ARCHITECTURE.md): control plane, app root, and CI/CD flow
- [GCP Landing Zone](architecture/gcp-landing-zone.md): folder/project model, two-root layer map, and Shared VPC hub-spoke topology
- [AWS Landing Zone](architecture/aws-landing-zone.md): multi-account SRA model, layer map, and network/security topology
- [Cross-Cloud Comparison](architecture/cross-cloud-comparison.md): where each capability lives per provider, side by side
- [Provider Selection](architecture/provider-selection.md): per-cloud-root model and any-combination matrix
- [Adding a Cloud](architecture/adding-a-cloud.md): per-cloud-root contract for extending the platform

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
