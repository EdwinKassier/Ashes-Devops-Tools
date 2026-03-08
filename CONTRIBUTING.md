# Contributing to Ashes DevOps Tools

This repository is centered on two supported Terraform roots:

- `envs/organization`
- `envs/apps`

Contributions should preserve that operator model and keep the repository easy to validate locally.

## Local Setup

```bash
make install
make pre-commit-install
```

`make install` manages repo tooling. Terraform itself must already be installed separately.

## Workflow

1. Create a short descriptive branch.
2. Make the change.
3. Run the fast local checks:

```bash
make fmt-check
make docs-check
make security
```

4. Run the deeper checks when your machine can support them:

```bash
make validate-all
make lint
```

Notes:

- `make validate-all` requires access to `registry.terraform.io`.
- `make lint` requires a healthy local TFLint Google ruleset plugin.

## Module Standards

Every supported module should include:

```text
main.tf
variables.tf
outputs.tf
versions.tf
README.md
```

Keep generated README sections current with:

```bash
make docs
```

## Planning Changes

### Control Plane

```bash
make plan-organization
```

### App Environment

```bash
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
```

## Pull Requests

Before opening a PR:

- keep docs current
- keep security findings intentional and documented
- avoid reintroducing separate deployable `dev`, `uat`, or `prod` roots
- do not add demo workloads to deployable roots

## Release Model

- GitHub validates code on pull requests.
- Terraform Cloud remains the source of truth for live state and apply runs.
- GitHub release tags such as `organization/vX.Y.Z` and `apps/<env>/vX.Y.Z` publish metadata after verifying a successful Terraform Cloud run.
- Those tags do not perform a live apply.
