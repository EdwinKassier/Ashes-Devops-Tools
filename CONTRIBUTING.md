# Contributing to Ashes DevOps Tools

Thank you for your interest in contributing! This document outlines the standards and workflows for developing, testing, and submitting changes to this repository.

## Development Workflow

### 1. Prerequisites
Ensure you have the required tools installed. We provide a `make` target for this:

```bash
make install
```

This installs Terraform, TFLint, TFSec, Checkov, terraform-docs, and pre-commit.

### 2. Branching Strategy
We use a feature-branch workflow:
- **`main`**: The stable production branch.
- **`feature/*`**: For new features (e.g., `feature/add-cloud-sql`).
- **`fix/*`**: For bug fixes (e.g., `fix/firewall-rule`).
- **`docs/*`**: For documentation updates.

### 3. Making Changes
1. Create a new branch: `git checkout -b feature/my-feature`
2. Make your code changes.
3. Run local quality checks frequently:
   ```bash
   make fmt         # Format code
   make validate-all # Validate syntax
   make lint        # Lint code
   ```

## Module Development

When creating or modifying modules in `modules/`:

1. **Structure**: Follow the standard structure:
   ```text
   modules/my-module/
   ├── main.tf
   ├── variables.tf
   ├── outputs.tf
   ├── versions.tf
   └── README.md (auto-generated)
   ```
2. **Documentation**: **Do not edit README.md manually.** Add descriptions to `variables.tf` and `outputs.tf`, then run:
   ```bash
   make docs
   ```
3. **Versions**: Always define `terraform` and `required_providers` versions in `versions.tf`.

## Testing

We use a multi-layer testing approach:

### 1. Static Analysis (Local)
Run before every commit:
```bash
make ci
```
This runs `fmt`, `validate`, `lint` (TFLint), and `security` (TFSec/Checkov).

### 2. Pre-commit Hooks
Git hooks will automatically run basic checks when you commit. Install them with:
```bash
make pre-commit-install
```

### 3. Integration Testing (Dry Run)
Before submitting a PR, verify your changes against the `dev` environment:
```bash
cd envs/dev
terraform plan
```
Ensure the plan matches your expectations and doesn't destroy critical resources.

## Deployment

Deployments are automated via GitHub Actions, but can be run locally by authorized admins.

### Standard Flow
1. **Dev**: Auto-deployed on merge to `main` (or via `apply-dev` manually).
2. **UAT**: Deployed via git tag `env/uat/vX.Y.Z`.
3. **Prod**: Deployed via git tag `env/prod/vX.Y.Z` (requires manual approval).

See `docs/architecture/ARCHITECTURE.md` for the full CI/CD detailed flow.

## Pull Requests

1. Push your branch to GitHub.
2. Fill out the **Pull Request Template** completely.
3. Ensure all CI checks pass.
4. Request review from a team member.
