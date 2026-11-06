# Application golden path — one service, end to end (envs/gcp/workload).
#
# Layer this on top of your environment tfvars:
#   TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload plan \
#     -var-file=terraform.tfvars -var-file=../../../examples/app-services/dev.app-services.tfvars
#
# What it creates in the dev host project (modules/gcp/stages/app-services):
#   - Artifact Registry docker repo  europe-west1-docker.pkg.dev/<host>/orders-api
#   - runtime SA  orders-api-run@<host>.iam.gserviceaccount.com (no project roles)
#   - Cloud Run v2 service  orders-api  (INTERNAL ingress, Direct VPC egress to the
#     env VPC's first private subnet, min 0 instances, secrets from Secret Manager)
#   - Cloud SQL Postgres  orders-api-db  (private IP via the host VPC's PSA,
#     IAM auth; the runtime SA is the IAM database user)
#   - deploy SA  orders-api-deploy@<host>.iam.gserviceaccount.com, impersonable
#     only by GitHub Actions in repository_id 987654321 on refs/heads/main
#
# Then read the GitHub variables for the delivery workflow:
#   terraform -chdir=envs/gcp/workload output -json app_github_actions

# App-only Workload Identity pool (apps-dev) in the host project, separate from
# the infrastructure pool in gcp-bootstrap.
enable_app_deploy_wif = true

# Optional defence in depth: the numeric GitHub org ID (gh api orgs/<org> --jq .id).
github_repository_owner_id = "12345678"

app_services = {
  orders-api = {
    # Image used only for the first revision; the pipeline owns the image
    # afterwards (Terraform ignores later image changes). Unset = the root's
    # app_bootstrap_image (gcp.workload.bootstrap_image), else the public
    # us-docker.pkg.dev/cloudrun/container/hello sample.
    # image = "europe-west2-docker.pkg.dev/<host>/mirror/hello:bootstrap"

    # ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"        # default
    # Public: list the service in public_ingress_services (or
    # gcp.workload.public_ingress.<env>) — ingress then defaults to
    # INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER behind a global external ALB.
    min_instances = 0
    max_instances = 5

    env_vars = {
      LOG_LEVEL = "info"
    }

    # The secret must already exist in the host project (create the container
    # with modules/gcp/data/secret-manager, set the value out of band). The
    # runtime SA gets secretAccessor on exactly these secrets.
    secrets = {
      STRIPE_API_KEY = { secret = "orders-api-stripe-key", version = "latest" }
    }

    # Private-IP Cloud SQL Postgres with IAM database authentication. The
    # service receives DB_INSTANCE_CONNECTION_NAME, DB_IAM_USER and DB_NAME.
    database = {
      databases = ["orders"]
      # enable_high_availability = true # production
    }

    # Deploy identity. repository_id is the IMMUTABLE numeric ID
    # (gh api repos/acme/orders-api --jq .id), so a renamed or re-created repo
    # with the same name cannot deploy.
    github = {
      repository_id = "987654321"
      repository    = "acme/orders-api"
      ref           = "refs/heads/main"
    }

    # enable_binary_authorization = true # enforce the project default policy
  }
}
