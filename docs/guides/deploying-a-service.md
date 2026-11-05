# Deploying a Service (the golden path)

The landing zone gives you a governed, networked, secured environment. This guide
shows how a service team runs an application on it. On GCP the golden path is
**implemented in code**: you add one entry to the `app_services` map in the
`gcp-workload-<env>` workspace, and `modules/gcp/stages/app-services` (called
once from `envs/gcp/workload/main.tf`) creates everything below. The default
(`app_services = {}`, every flag off) creates nothing.

## What one `app_services` entry creates (GCP)

All resources land in the **environment host project** (`environment_config[<env>].host_project_id`
from `gcp-projects`), on the **environment Shared VPC**, not the hub.

| Resource | Name | Notes |
|----------|------|-------|
| Artifact Registry docker repo | `<region>-docker.pkg.dev/<host>/<svc>` | Immutable tags; cleanup policies (keep the 20 most recent versions, delete untagged after 7 days); optional CMEK via `artifact_registry_kms_key_name`. |
| Runtime service account | `<svc>-run@<host>.iam.gserviceaccount.com` | No project roles. It gets `secretmanager.secretAccessor` on the secrets it references only, plus Cloud SQL client/instanceUser conditioned to its own instance when it has a database. |
| Cloud Run v2 service | `<svc>` | `INGRESS_TRAFFIC_INTERNAL_ONLY` by default, Direct VPC egress (`PRIVATE_RANGES_ONLY`) to the env VPC's first private subnet, min 0 / max 10 instances, secrets from Secret Manager, optional Binary Authorization, deletion protection follows `enable_deletion_protection`. |
| Cloud SQL Postgres (optional `database`) | `<svc>-db` | Private IP only through the env VPC's Private Service Access (the host stage creates it by default: `enable_private_service_access = true`). TLS-only, backups + PITR, IAM database auth. The runtime SA is the IAM database user. Edition `ENTERPRISE` with `db-custom-1-3840`. |
| Deploy identity (optional `github`) | `<svc>-deploy@<host>.iam.gserviceaccount.com` | Impersonable only through the app-deploy WIF pool, by the GitHub repo's **immutable numeric `repository_id`** (optionally a ref and/or a GitHub environment). Roles: `run.developer` on the service, `artifactregistry.writer` on the repo, `iam.serviceAccountUser` on the runtime SA only. |

The app-deploy Workload Identity pool (`apps-<env>`, provider `github`) lives in
the env host project, separate from the infrastructure pool that `gcp-bootstrap`
creates. Turn it on with `enable_app_deploy_wif = true`. Optionally set
`enable_gke_autopilot = true` for one private GKE Autopilot cluster
(`<env>-apps`) per environment. It is off by default.

## Step 1: prerequisites

1. `gcp-projects`, `gcp-network-hub` and `gcp-workload-<env>` are applied (the host
   VPC, subnets and PSA exist).
2. Look up the app repository's numeric IDs. Never use the `owner/name` form, because
   a deleted and re-created repository with the same name would otherwise inherit
   deploy access:

   ```bash
   gh api repos/acme/orders-api --jq .id   # repository_id, e.g. 987654321
   gh api orgs/acme --jq .id               # optional github_repository_owner_id
   ```

3. Create any runtime secrets the service reads in the host project, and set the
   values out of band. Secret values never pass through Terraform or the pipeline:

   ```bash
   gcloud secrets create orders-api-stripe-key --project <host> --replication-policy automatic
   printf '%s' "$STRIPE_KEY" | gcloud secrets versions add orders-api-stripe-key --project <host> --data-file=-
   ```

   (Or declare the secret container with `modules/gcp/data/secret-manager`.)

## Step 2: add the entry (tfvars)

In the `gcp-workload-<env>` workspace variables (or your tfvars):

```hcl
enable_app_deploy_wif      = true
github_repository_owner_id = "12345678" # optional, numeric org ID

app_services = {
  orders-api = {
    env_vars = { LOG_LEVEL = "info" }
    secrets  = { STRIPE_API_KEY = { secret = "orders-api-stripe-key" } }
    database = { databases = ["orders"] }
    github = {
      repository_id = "987654321"        # immutable numeric ID
      repository    = "acme/orders-api"  # informational only
      ref           = "refs/heads/main"  # optional: only this ref may deploy
      # environment = "dev"              # optional: only this GitHub environment
    }
  }
}
```

A fully commented version is in
[`examples/app-services/dev.app-services.tfvars`](../../examples/app-services/dev.app-services.tfvars).
The typed shape, with every default, is the `services` variable of
[`modules/gcp/stages/app-services`](../../modules/gcp/stages/app-services/README.md).
Common optional fields include `image` (bootstrap image, default
`us-docker.pkg.dev/cloudrun/container/hello`), `ingress`, `cpu`, `memory`,
`min_instances`, `max_instances`, `subnetwork_id`, `invoker_members`,
`enable_unauthenticated`, `enable_binary_authorization` / `binary_authorization_policy`,
`runtime_project_roles` (an escape hatch, empty by default), `artifact_registry`
(cleanup tuning) and `database.{tier,edition,enable_high_availability,encryption_key_name}`.

Terraform Cloud plans and applies the change. The first apply creates the service
with the bootstrap image.

When a database is declared, the service receives `DB_INSTANCE_CONNECTION_NAME`,
`DB_IAM_USER` and `DB_NAME`. Connect with the Cloud SQL language connector (or the
Auth Proxy) using automatic IAM authentication as `DB_IAM_USER`. No password
exists. You must still grant the IAM user privileges inside Postgres (for
example `GRANT ALL ON DATABASE orders TO "orders-api-run@<host>.iam"`) as a
one-time step by a database admin.

## Step 3: wire the delivery pipeline

Read the per-service values from the workspace:

```bash
terraform -chdir=envs/gcp/workload output -json app_github_actions
# {"orders-api":{"GCP_WIF_PROVIDER":"projects/<host-number>/locations/global/workloadIdentityPools/apps-dev/providers/github",
#                "GCP_DEPLOY_SA":"orders-api-deploy@<host>.iam.gserviceaccount.com",
#                "GCP_PROJECT_ID":"<host>","GCP_REGION":"europe-west1",
#                "CLOUD_RUN_SERVICE":"orders-api",
#                "IMAGE_REPOSITORY":"europe-west1-docker.pkg.dev/<host>/orders-api/orders-api"}}
```

Set each key as a GitHub Actions **variable** (not a secret: none of them is
sensitive) on the app repository, or on the GitHub environment if you declared
`github.environment`. Then copy
[`examples/app-delivery/cloud-run-delivery.example.yml`](../../examples/app-delivery/cloud-run-delivery.example.yml)
to `.github/workflows/deploy.yml` in the app repository. Its core steps are:

```yaml
permissions:
  contents: read
  id-token: write
steps:
  - uses: google-github-actions/auth@v2 # pin to a SHA in your app repo
    with:
      workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
      service_account: ${{ vars.GCP_DEPLOY_SA }}
  - run: |
      gcloud auth configure-docker "${{ vars.GCP_REGION }}-docker.pkg.dev" --quiet
      docker build -t "${{ vars.IMAGE_REPOSITORY }}:${GITHUB_SHA}" .
      docker push "${{ vars.IMAGE_REPOSITORY }}:${GITHUB_SHA}"
      gcloud run deploy "${{ vars.CLOUD_RUN_SERVICE }}" --project "${{ vars.GCP_PROJECT_ID }}" \
        --region "${{ vars.GCP_REGION }}" --image "${{ vars.IMAGE_REPOSITORY }}:${GITHUB_SHA}" --quiet
```

The full example also scans the image with Trivy, using the same CRITICAL/HIGH bar
as the IaC gate, before it pushes. The `google-github-actions/deploy-cloudrun`
action is an equivalent replacement for the `gcloud run deploy` step.

**Who owns what:** Terraform owns the service *configuration* (ingress, VPC egress,
secrets, runtime SA, scaling). The pipeline owns the *image*. The Cloud Run module
ignores image and client changes, so Terraform runs never roll back a deploy.
Change configuration in `app_services`, not with `gcloud run deploy --set-*` flags.
Terraform would revert those flags on its next apply.

## Exposing the service (front door)

The default ingress is internal only, so callers inside the VPC (and peered
networks) can reach it. To publish the service on your own domain behind a global
HTTPS load balancer with a managed certificate, set
`ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"` on the entry and add
`modules/gcp/network/app-ingress`:

```hcl
module "ingress" {
  source                 = "../../../modules/gcp/network/app-ingress"
  project_id             = local.env_config.host_project_id
  region                 = local.env_config.region
  name                   = "orders-api"
  domains                = ["api.example.com"]
  cloud_run_service_name = module.app_services.services["orders-api"].service_name
  dns_managed_zone       = "app-zone"  # optional: creates the A record for you
  # security_policy_id   = module.host.security_policy_id  # optional Cloud Armor WAF
}
```

For a deliberately public, unauthenticated endpoint, also set
`enable_unauthenticated = true`. To grant specific callers, use
`invoker_members = ["serviceAccount:caller@..."]`.

## GKE Autopilot

`enable_gke_autopilot = true` creates one private Autopilot cluster on the env VPC's
first private subnet (private nodes, private endpoint, Workload Identity, Gateway
API). Workloads and their deploy identity are not generated for GKE yet. Use
[`examples/app-delivery/gke-autopilot-delivery.example.yml`](../../examples/app-delivery/gke-autopilot-delivery.example.yml)
with a deploy SA that you grant `roles/container.developer` yourself.

## AWS golden path (containers)

Implemented in code: add an entry to `services` in `aws-workload-<env>`. See
[AWS](#aws) at the end of this guide.

## What is still your responsibility

- The application's own Postgres grants for its IAM user, and schema migrations.
- Any extra runtime roles (`runtime_project_roles` is empty by default, so keep it
  minimal).
- The content of your domain's DNS zone.
- Service objectives: attach `modules/gcp/monitoring/slo` to the service.
- Promotion: add the same entry to the next environment's tfvars (a new deploy SA
  and provider are created per environment). See
  [`../runbooks/promotion.md`](../runbooks/promotion.md).

## Caveats to validate on real GCP

These items are verified by mocked plan tests only:

- **VPC-SC.** If the env perimeter is enforced and restricts `run`,
  `artifactregistry` or `sqladmin`, add an ingress rule for the app-deploy WIF
  pool (`principalSet://iam.googleapis.com/projects/<host-number>/locations/global/workloadIdentityPools/apps-<env>/*`).
  The bootstrap image `us-docker.pkg.dev/cloudrun/container/hello` lives outside
  the perimeter, so pre-push a bootstrap image into the service's own repo and set
  `image` if pulls are blocked.
- **Binary Authorization.** The bootstrap image must satisfy the policy, or the
  first apply fails.
- **Shared repos.** If two services share one GitHub repository with *different*
  `ref`/`environment` constraints, the provider condition is the union of both. A
  token that satisfies either constraint can impersonate both deploy SAs. Give each
  constraint its own repository, or use the same constraint for both.
- **Pool IDs.** A WIF pool ID stays reserved for 30 days after deletion. Set
  `app_deploy_wif_pool_id` if you need to re-create a pool sooner.

## AWS

On AWS the golden path is also **implemented in code**: add one entry to the
`services` map in the `aws-workload-<env>` workspace, and
`modules/aws/stages/app-services` (called once from `envs/aws/workload/main.tf`)
creates everything below in that environment's workload account. The default
(`services = {}`, `enable_github_oidc = false`) creates nothing.

### What one `services` entry creates (AWS)

| Resource | Details |
|----------|---------|
| ECR repository `<service>` | IMMUTABLE tags, scan on push, encrypted with the workload CMK (`kms_key_arn`), lifecycle: untagged images expire after 7 days, last 100 tagged kept |
| Log group `/ecs/<env>/<service>` | CMK-encrypted, 365-day retention (`app_log_retention_days`) |
| Task execution role `<env>-<service>-exec` | pulls **its** repo, writes **its** log group, reads **its** `secrets` (+ `kms:Decrypt`); trust is `ecs-tasks` with an `aws:SourceAccount` guard |
| Task role `<env>-<service>-task` | empty: add `task_role_policy_json` / `task_role_managed_policy_arns` |
| ECS Fargate service `<service>` | private subnets, no public IP, deployment circuit breaker with rollback, registered (by IP) with the shared ALB |
| Deploy role `<env>-<service>-deploy` (when `github` is set and `enable_github_oidc = true`) | trust: `aud = sts.amazonaws.com` **and** an exact `sub` (StringEquals; wildcards rejected). Permissions: push to its ECR repo, `ecs:RegisterTaskDefinition`/`DescribeTaskDefinition`, `ecs:UpdateService`/`DescribeServices` on its service only, `iam:PassRole` on its own two task roles (to `ecs-tasks.amazonaws.com` only) |
| Aurora PostgreSQL `<env>-<service>` (when `database` is set) | Serverless v2 by default; RDS-managed master password in Secrets Manager (never in state); CMK; isolated subnets; SG allows 5432 from the service SG only. The task gets `DB_HOST`, `DB_PORT`, `DB_NAME` and the `DB_USERNAME` / `DB_PASSWORD` secrets |
| CloudWatch alarms | CPU, memory, unhealthy targets, target 5xx (`enable_app_alarms`, `app_alarm_sns_topic_arn`) |

Shared per environment, created only when `services` is non-empty:

- ECS cluster `<env>-apps` (Container Insights).
- One **internal** ALB `<env>-apps` in the private tier. Its default action is a
  404, and each service gets a listener rule (default path `/<service>` and
  `/<service>/*`; set `path_patterns` / `host_headers` / `priority` to override).
  Without `app_alb_certificate_arn` it listens on HTTP :80 inside the private
  network only. With a certificate it serves HTTPS :443 and redirects :80.
  Ingress defaults to the spoke CIDR (`app_alb_ingress_cidrs` widens it, for
  example to the org supernet for other spokes over the TGW).
- The account's GitHub OIDC provider (`token.actions.githubusercontent.com`,
  audience `sts.amazonaws.com`), created once when `enable_github_oidc = true`.
  If something else already owns it in the account, set
  `create_github_oidc_provider = false` and pass `github_oidc_provider_arn`.

### Step 1: prerequisites (AWS)

- The `aws-workload-<env>` workspace is applied: spoke VPC with `private` and
  `isolated` tiers, TGW default route to central egress.
- `kms_key_arn` is set to a CMK whose key policy admits
  `logs.<region>.amazonaws.com` (log groups) and lets the account's IAM
  principals use it (execution roles decrypt secrets, ECR, RDS).
- In the service's GitHub repository, create a GitHub **environment** named after
  the AWS environment (for example `dev`). Protection rules on it, such as
  required reviewers for `prod`, become part of the trust: the deploy role only
  accepts tokens from jobs that run in that environment.

### Step 2: add the entry (AWS tfvars)

```hcl
# envs/aws/workload — TF_WORKSPACE=aws-workload-dev
enable_github_oidc = true

services = {
  orders = {
    container_port    = 8080
    cpu               = 512
    memory            = 1024
    health_check_path = "/healthz"
    environment       = { LOG_LEVEL = "info" }
    secrets           = { STRIPE_KEY = "arn:aws:secretsmanager:eu-west-2:222222222222:secret:orders/stripe-AbCdEf" }

    # Deploy role trusts ONLY: repo:acme/orders:environment:dev
    github = { repository = "acme/orders" }

    database = {} # optional Aurora PostgreSQL
  }
}
```

OIDC subject options, in order of precedence:

| `github` field | Trusted `sub` |
|----------------|---------------|
| `subject = "..."` | exactly that string. Use this with a **customised sub claim template** (below) |
| `ref = "refs/heads/main"` | `repo:acme/orders:ref:refs/heads/main` |
| default (or `environment = "dev-approval"`) | `repo:acme/orders:environment:<env>` |

**Immutable repository IDs and reusable workflows.** IAM can only evaluate the
`sub` and `aud` claims of a GitHub token. It cannot evaluate `repository_id` or
`job_workflow_ref`. The default `sub` names the repository, so a renamed or
deleted-and-recreated `org/repo` would inherit the trust. To pin the immutable
IDs, or a reusable deploy workflow, put them **into** `sub` using GitHub's OIDC
customisation API, then set `github.subject` to the resulting string:

```sh
gh api -X PUT repos/acme/orders/actions/oidc/customization/sub \
  -f 'use_default=false' \
  -f 'include_claim_keys[]=repository_owner_id' \
  -f 'include_claim_keys[]=repository_id' \
  -f 'include_claim_keys[]=environment'
# sub is now: repository_owner_id:<id>:repository_id:<id>:environment:dev
```

The apply (via TFC) outputs `app_services["orders"]` with everything the
pipeline needs: `ecr_repository_url`, `deploy_role_arn`, `ecs_cluster_name`,
`ecs_service_name`, `task_definition_family` (`<env>-<service>`) and
`container_name`. Copy these into the GitHub environment's **variables**. None
of them are secrets.

The first task-definition revision runs `<ecr-repo>:bootstrap` (or
`container_image` if set). Until the first pipeline run pushes an image, tasks
fail to start and the circuit breaker keeps retrying, so expect the service to
be unhealthy until then. Once a service has a deploy role, the ECS service
**ignores** `task_definition` and `desired_count` drift, so Terraform never
reverts what CI deployed.

### Step 3: the delivery pipeline (GitHub Actions)

Put this in the **service** repository as `.github/workflows/deploy.yml`. It is
documentation, not a workflow in this repo. Actions are referenced by version
tag for readability. **Pin each one to a full commit SHA in your repository.**

```yaml
name: deploy

on:
  push:
    branches: [main]

permissions:
  contents: read
  id-token: write # mint the GitHub OIDC token

concurrency:
  group: deploy-dev
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    # REQUIRED: the job's environment is what the deploy role's sub trusts
    # (repo:acme/orders:environment:dev). A job without it is refused.
    environment: dev
    env:
      AWS_REGION: eu-west-2
      ECR_REPOSITORY_URL: ${{ vars.ECR_REPOSITORY_URL }}       # app_services.orders.ecr_repository_url
      ECS_CLUSTER: ${{ vars.ECS_CLUSTER }}                     # app_services.orders.ecs_cluster_name
      ECS_SERVICE: ${{ vars.ECS_SERVICE }}                     # app_services.orders.ecs_service_name
      TASK_DEFINITION_FAMILY: ${{ vars.TASK_DEFINITION_FAMILY }} # app_services.orders.task_definition_family
      CONTAINER_NAME: ${{ vars.CONTAINER_NAME }}               # app_services.orders.container_name
    steps:
      - uses: actions/checkout@v4 # pin to a SHA

      - name: Configure AWS credentials (OIDC, no stored keys)
        uses: aws-actions/configure-aws-credentials@v4 # pin to a SHA
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }} # app_services.orders.deploy_role_arn
          aws-region: ${{ env.AWS_REGION }}
          # audience defaults to sts.amazonaws.com, the aud the role requires

      - name: Log in to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2 # pin to a SHA

      - name: Build and push (immutable tag = commit SHA)
        run: |
          docker build -t "${ECR_REPOSITORY_URL}:${GITHUB_SHA}" .
          docker push "${ECR_REPOSITORY_URL}:${GITHUB_SHA}"

      - name: Fetch the current task definition
        run: |
          aws ecs describe-task-definition \
            --task-definition "${TASK_DEFINITION_FAMILY}" \
            --query taskDefinition > task-definition.json

      - name: Render the new image into the task definition
        id: render
        uses: aws-actions/amazon-ecs-render-task-definition@v1 # pin to a SHA
        with:
          task-definition: task-definition.json
          container-name: ${{ env.CONTAINER_NAME }}
          image: ${{ env.ECR_REPOSITORY_URL }}:${{ github.sha }}

      - name: Deploy to ECS and wait for a steady state
        uses: aws-actions/amazon-ecs-deploy-task-definition@v2 # pin to a SHA
        with:
          task-definition: ${{ steps.render.outputs.task-definition }}
          cluster: ${{ env.ECS_CLUSTER }}
          service: ${{ env.ECS_SERVICE }}
          wait-for-service-stability: true
```

The deploy role allows exactly these calls. Anything else, such as tagging the
task definition (`ecs:TagResource`), creating repositories, or passing another
role, is denied. Before the push step you can add an image scan, as the
reference pipeline
[`examples/app-delivery/ecs-fargate-delivery.example.yml`](../../examples/app-delivery/ecs-fargate-delivery.example.yml)
does with Trivy. ECR also scans on push. For promotion to `prod`, add a second
job (or workflow) with `environment: prod` that uses the prod workspace's
outputs. Each environment's deploy role is in its own account and trusts only
its own GitHub environment.

### Exposing an AWS service

The ALB is internal. It is reachable from the spoke and, through
`app_alb_ingress_cidrs`, from other spokes over the TGW. Internet exposure
belongs at the edge (`enable_edge`: CloudFront + WAF in us-east-1). An
internet-facing ALB (`app_alb_internal = false`) needs a public subnet tier
(`app_alb_subnet_tier`) and `app_alb_certificate_arn`. The default spoke has no
public tier.

### Caveats to validate on real AWS

These items are verified by mocked plan tests only:

- **CloudFront to internal ALB.** The edge module's origin is a public HTTPS
  hostname. Fronting the internal ALB needs a CloudFront **VPC origin**, which
  `edge-security` does not yet wire.
- **KMS key policy.** CloudWatch Logs must be allowed in the CMK policy, or log
  group creation fails. The execution roles need `kms:Decrypt` through the key
  policy too, if the policy does not delegate to IAM.
- **Egress.** Tasks reach ECR, Logs and Secrets Manager over HTTPS through the
  TGW default route to central egress. If the hub does not provide internet
  egress, add interface endpoints (`ecr.api`, `ecr.dkr`, `logs`,
  `secretsmanager`) to the spoke. S3 (for ECR layers) already has a gateway
  endpoint.
- **Bootstrap image.** The first revision references `:bootstrap`, which does
  not exist until you push it. Push a placeholder, set `container_image`, or
  accept failing tasks until the first pipeline run.
- **Database credentials.** The app receives the RDS **master** credentials.
  Create a least-privilege application role (or use IAM database auth, which is
  enabled) and switch `secrets` to it before production.
- **Deletion guard.** Removing a service that has a `database` fails the plan.
  `rds-aurora`'s `terraform_data` deletion guard and AWS deletion protection
  must be removed deliberately first.
- **One OIDC provider per account.** If the account already has a
  `token.actions.githubusercontent.com` provider, the create fails with
  `EntityAlreadyExists`. Use `create_github_oidc_provider = false`.
