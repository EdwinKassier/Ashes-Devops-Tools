# Troubleshooting Guide

Common local and workflow failures for this repository.

## `make install` finishes but Terraform is still missing

`make install` manages repo tooling, not Terraform itself.

```bash
terraform version
```

If Terraform is missing, install it separately before running any Terraform command.

## `make validate-all` fails with `Failed to query available provider packages`

`make validate-all` runs `terraform init -backend=false` for each supported root. It still needs access to `registry.terraform.io`.

Check:

- outbound network access
- DNS resolution
- proxy settings

## `make lint` fails with `Unrecognized remote plugin message`

That usually means the local TFLint Google ruleset plugin is broken or incompatible.

Reset the plugin cache:

```bash
rm -rf ~/.tflint.d/plugins
tflint --init
make lint
```

## `make docs-check` reports a README is out of date

Regenerate docs and re-run the check:

```bash
make docs
make docs-check
```

If the file is still out of date, confirm the module has:

- `main.tf`
- `variables.tf`
- `outputs.tf`
- `versions.tf`
- `README.md`

## `make security` fails

The local security target runs TFSec and Checkov.

Use the component commands while debugging:

```bash
tfsec . --config-file .tfsec.yml --exclude-path examples
checkov -d modules --framework terraform
checkov -d envs --framework terraform
```

## The wrong application environment is selected

`envs/apps` is keyed by Terraform Cloud workspace, not by directory name.

Always verify the workspace before planning:

```bash
echo "$TF_WORKSPACE"
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
```

## `envs/apps` cannot find the organization remote state

By default, `envs/apps` reads outputs from the Terraform Cloud workspace named `organization`.

Verify:

- `tfc_organization` is correct
- `organization_workspace_name` is still `organization`, unless intentionally overridden
- the `organization` workspace has already been applied

## Release tags do not trigger

The release-metadata workflow only listens for:

```text
organization/vX.Y.Z
apps/<env>/vX.Y.Z
```

Examples:

```bash
git tag -a organization/v1.0.0 -m "Organization v1.0.0"
git push origin organization/v1.0.0

git tag -a apps/dev/v1.0.0 -m "Apps dev v1.0.0"
git push origin apps/dev/v1.0.0
```

Those tags publish release metadata after a successful Terraform Cloud run. They do not perform a live apply.

## Pre-commit hooks fail because `core.hooksPath` is set

```bash
git config --unset core.hooksPath
make pre-commit-install
```

## Need more detail from Terraform

```bash
export TF_LOG=DEBUG
TF_WORKSPACE=apps-dev terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
```
