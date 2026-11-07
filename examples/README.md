# Examples

Reference material for this landing zone. Nothing here is a deployable root.

- [`system-design/`](system-design/): system design interview walkthroughs
  grounded in this landing zone, AWS and GCP side by side. Start with the
  [primer](system-design/00-primer.md).
- [`app-delivery/`](app-delivery/): reference GitHub Actions delivery
  pipelines for Cloud Run, ECS Fargate and GKE Autopilot, to copy into an
  application repository.
- [`app-services/`](app-services/): a tfvars overlay for the GCP application
  golden path, one service end to end in `envs/gcp/workload`.
- [`aws-landing-zone/`](aws-landing-zone/): the operator walkthrough for
  standing up the AWS landing zone, with example tfvars per root.
- [`cloud-armor/`](cloud-armor/): a Cloud Armor WAF policy with OWASP managed
  rules.
- [`cloud-storage/`](cloud-storage/): CMEK-encrypted application buckets.
- [`kms/`](kms/): a Cloud KMS key ring with CMEK keys.
- [`presets/`](presets/): ready-to-use `-var-file` overlays that set a handful
  of toggles.
- [`vpc-sc/`](vpc-sc/): a VPC Service Controls perimeter around BigQuery,
  Cloud Storage and Secret Manager.
- [`workloads/`](workloads/): attaching a service project to an environment's
  Shared VPC host.

The loose file [`dev.tfvars.example`](dev.tfvars.example) is the example
environment overlay used by `make plan-gcp-workload`.
