# Monitoring Modules

This directory groups monitoring and dashboard modules. It is a category index, not a deployable Terraform module.

## Modules

| Module | Purpose |
|---|---|
| [`alert_policy`](./alert-policy/) | Cloud Monitoring alert policies and email / webhook notification channels |
| [`compute_dashboard`](./compute-dashboard/) | GCP dashboard resources for compute-oriented observability |

## Usage Guidance

- Use these modules from a real root or stage composition rather than applying this directory directly.
- Refer to the concrete module README for required providers and arguments.
