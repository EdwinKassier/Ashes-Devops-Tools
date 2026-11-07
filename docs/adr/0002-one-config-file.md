# ADR 0002: One committed configuration file

- Status: Accepted
- Date: 2026-11-07

## Context

Forks need to configure about a dozen roots across four providers. Per-root tfvars files drift apart, and VCS-driven HCP Terraform runs would need variables set by hand on every workspace.

## Decision

One committed file, `config/landing-zone.yaml` (schema and placeholders in `config/landing-zone.example.yaml`; scaffolded by `scripts/init-landing-zone.sh`), feeds every root under `envs/**`. Each root has a `config.tf` where `local.lz` is the decoded file (path in `landing_zone_config_path`, `""` disables it) and `local.cfg` holds the config-only values. Precedence is explicit variable (tfvars or workspace variable), then the config file, then the built-in default. Config-backed variables default to `null`, and validations check the effective value so an unset value or untouched placeholder fails the plan naming the config key. The file holds no secrets. Per-workspace overrides live in `config/tfc-workspaces.yaml`.

## Consequences

- VCS-driven runs need no tfvars, and tfc-admin derives workspaces and project names from the same file.
- Every new setting is added in several places (schema, example, root `config.tf`, variable); `make config-check` and the consistency checks guard the drift.
- Tests isolate themselves with `landing_zone_config_path = ""` or use `tests/fixtures/landing-zone*.yaml`.
