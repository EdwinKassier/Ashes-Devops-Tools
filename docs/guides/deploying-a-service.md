# Deploying a Service (the golden path)

The landing zone gives you a governed, networked, secured account. This guide
shows how to run an actual application on it with the platform modules (audit
C1). Everything is opt-in: you compose the modules you need.

Two runtimes per cloud are provided. Pick one:

- Serverless: `modules/gcp/compute/cloud-run` or `modules/aws/compute/ecs-fargate`.
- Kubernetes: `modules/gcp/compute/gke-autopilot` (AWS EKS is a follow-on).

Data and secrets:

- `modules/gcp/data/cloud-sql` or `modules/aws/data/rds-aurora` (PostgreSQL).
- `modules/gcp/data/secret-manager` (GCP app secret store).

## GCP golden path (serverless)

Compose the three modules in a workload root (`envs/gcp/workload`), reading the
host project and network from remote state. The service reads its secrets
directly from Secret Manager, so secret values never pass through Terraform state
or the delivery pipeline.

```hcl
module "secrets" {
  source     = "../../../modules/gcp/data/secret-manager"
  project_id = local.env_config.host_project_id
  secrets = {
    "database-url" = { replication = { user_managed_regions = [] } }
  }
  secret_accessors = {
    "database-url" = ["serviceAccount:${google_service_account.app.email}"]
  }
  # Set the value out-of-band (gcloud/console), not here.
}

module "database" {
  source          = "../../../modules/gcp/data/cloud-sql"
  project_id      = local.env_config.host_project_id
  region          = local.env_config.region
  name            = "app-db"
  private_network = data.terraform_remote_state.network_hub.outputs.hub_network.vpc_self_link
  # enable_high_availability = true  # for production
}

module "service" {
  source                = "../../../modules/gcp/compute/cloud-run"
  project_id            = local.env_config.host_project_id
  location              = local.env_config.region
  name                  = "my-api"
  image                 = "europe-west1-docker.pkg.dev/${local.env_config.host_project_id}/apps/my-api:bootstrap"
  service_account_email = google_service_account.app.email
  secret_env_vars = [
    { name = "DATABASE_URL", secret = module.secrets.secret_short_ids["database-url"], version = "latest" }
  ]
  # ingress defaults to internal + load balancer; set enable_unauthenticated only
  # for a deliberately public service.
}
```

Apply this once to create the service with a placeholder image. From then on,
the delivery pipeline builds and ships new images.

## Exposing the service (front door)

Cloud Run gives the service an internal endpoint. To publish it on your own
domain behind a global HTTPS load balancer with a managed certificate, add
`modules/gcp/network/app-ingress`:

```hcl
module "ingress" {
  source                 = "../../../modules/gcp/network/app-ingress"
  project_id             = local.env_config.host_project_id
  region                 = local.env_config.region
  name                   = "my-api"
  domains                = ["api.example.com"]
  cloud_run_service_name = module.service.name
  dns_managed_zone       = "app-zone"  # optional: creates the A record for you
  # security_policy_id   = module.edge.policy_id  # optional Cloud Armor WAF
  # ssl_policy_id        = ...                     # optional TLS floor
}
```

The module serves HTTPS only (HTTP redirects), keeps backend access logging on,
and provisions a Google-managed certificate. The certificate turns active once
the domain resolves to the load balancer IP (`module.ingress.ip_address`). Cloud
Armor and a TLS-version floor are opt-in for internet-facing services.

## Delivery pipeline

`examples/app-delivery/cloud-run-delivery.example.yml` is a reference GitHub
Actions workflow: build, scan (Trivy, same CRITICAL/HIGH bar as the IaC gate),
push to Artifact Registry (keyless WIF, no SA keys), and deploy. Copy it into the
application repository and set the WIF provider and deploy SA from the
`gcp-bootstrap` outputs. For a GitOps model, have the pipeline bump the image
variable and let Terraform Cloud apply instead of calling `gcloud run` directly.

## AWS golden path (containers)

The shape is the same: `modules/aws/data/rds-aurora` (CMEK-encrypted, private,
password managed in Secrets Manager) plus `modules/aws/compute/ecs-fargate`
(private subnets, no public IP, secrets via `valueFrom`, optional ALB and
autoscaling), composed in `envs/aws/workload`. Point the task definition's
container secrets at the RDS-managed master-user secret ARN the data module
outputs.

## What is still your responsibility

These modules are the building blocks and the secure defaults. You still own the
application IAM role contents (least privilege is yours to define) and the content
of your domain's DNS zone. For service objectives, attach
`modules/gcp/monitoring/slo` to the workload's monitored service to track
availability or latency against a goal and alert on fast error-budget burn. A
formal dev to prod promotion flow is the next platform addition; until then,
promote by applying each environment's workspace in order.
