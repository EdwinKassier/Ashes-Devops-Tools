# Examples

Reference material for this landing zone. None of it is a landing-zone root:
the landing zone deploys only through `envs/` and its Terraform Cloud
workspaces. The five Terraform folders (`cloud-armor/`, `cloud-storage/`,
`kms/`, `vpc-sc/`, `workloads/`) are standalone sandboxes: plan them freely,
and apply them only in a scratch project or folder, never against a landing-zone
project.

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
  of toggles. `prod-gcp-workload` and `regulated-gcp-workload` also have YAML
  twins that `envs/gcp/workload` reads with no `-var-file`: the first when
  `config/landing-zone.yaml` names it, the second for every
  `compliance_class: regulated` environment.
- [`vpc-sc/`](vpc-sc/): a VPC Service Controls perimeter around BigQuery,
  Cloud Storage and Secret Manager.
- [`workloads/`](workloads/): attaching a service project to a Shared VPC
  host, standalone. In the landing zone, `gcp-workload-<env>` creates the
  environment subnets, and a team project belongs in
  `gcp.environments.<env>.service_teams` so it is inside the environment's
  VPC-SC perimeter.

The loose file [`dev.tfvars.example`](dev.tfvars.example) is the example
environment overlay used by `make plan-gcp-workload`.
