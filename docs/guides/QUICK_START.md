# Quick Start Guide

This guide gets the repository into a usable local state with the current `organization` and `apps` roots.

## Prerequisites

- macOS, Linux, or WSL2
- Git
- Terraform `>= 1.6.0`
- internet access for provider downloads
- GCP credentials for local plans

## 1. Clone the Repository

```bash
git clone https://github.com/EdwinKassier/Ashes-Devops-Tools.git
cd Ashes-Devops-Tools
```

## 2. Install Repo Tooling

```bash
make install
make pre-commit-install
```

`make install` installs repo-managed tools such as TFLint, TFSec, Checkov, terraform-docs, and pre-commit. Terraform itself must already be installed separately.

## 3. Authenticate to Google Cloud

```bash
gcloud auth application-default login
```

## 4. Initialize the Supported Roots

```bash
terraform -chdir=envs/organization init
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps init
```

## 5. Run Fast Local Checks

```bash
make fmt-check
make docs-check
make security
```

## 6. Run Deeper Checks When Available

```bash
make validate-all
make lint
```

Notes:

- `make validate-all` requires access to `registry.terraform.io`.
- `make lint` requires a working local TFLint Google ruleset plugin.

## 7. Plan Changes

### Control Plane

```bash
make plan-organization
```

### App Environment

```bash
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
```

## Verification Checklist

- `terraform version` reports `>= 1.6.0`
- `make help` prints the supported commands
- `make fmt-check`, `make docs-check`, and `make security` succeed
- `terraform -chdir=envs/organization init` succeeds
- `TF_WORKSPACE=apps-dev terraform -chdir=envs/apps init` succeeds

## Common Commands

| Command | Description |
|:---|:---|
| `make fmt-check` | Check Terraform formatting |
| `make docs-check` | Check terraform-docs drift |
| `make security` | Run local security scanners |
| `make validate-all` | Validate supported roots |
| `make lint` | Run TFLint across supported roots |
| `make plan-organization` | Plan control-plane changes |
| `make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars` | Plan an app environment |

## Next Steps

- Read the [Architecture Guide](../architecture/ARCHITECTURE.md)
- Read the [Contributing Guide](../../CONTRIBUTING.md)
- Use `examples/workloads/` as the starting point for a dedicated workload root
