# Deploying a Service (the golden path)

The landing zone gives you a governed, networked, secured environment. This guide
shows how a service team runs an application on it. On GCP the golden path is
**implemented in code**: you add one entry under `gcp.environments.<env>.services`
in `config/landing-zone.yaml`, open a PR, and after merge Terraform Cloud applies
the `gcp-workload-<env>` workspace. `modules/gcp/stages/app-services` (called once
from `modules/gcp/stages/environment`, which `envs/gcp/workload` deploys) creates everything below. With no entry (and
every flag off) nothing is created.

**One flow for every change:** edit `config/landing-zone.yaml` -> PR (CI plus a
Terraform Cloud speculative plan) -> merge -> the `config/**` trigger queues a
run -> approve the apply in Terraform Cloud. Never `terraform apply` locally. An
explicit `app_services` workspace variable still works and replaces the config
entry for that workspace.

## What one `services` entry creates (GCP)

All resources land in the **environment host project** (`environment_config[<env>].host_project_id`
from `gcp-projects`), on the **environment Shared VPC**, not the hub.

| Resource | Name | Notes |
|----------|------|-------|
| Artifact Registry docker repo | `<region>-docker.pkg.dev/<host>/<svc>` | Immutable tags; cleanup policies (keep the 20 most recent versions, delete untagged after 7 days); optional CMEK via `artifact_registry_kms_key_name`. |
| Runtime service account | `<svc>-run@<host>.iam.gserviceaccount.com` | No project roles. It gets `secretmanager.secretAccessor` on the secrets it references only, plus Cloud SQL client/instanceUser conditioned to its own instance when it has a database. |
| Cloud Run v2 service | `<svc>` | `INGRESS_TRAFFIC_INTERNAL_ONLY` by default, Direct VPC egress (`PRIVATE_RANGES_ONLY`) to the env VPC's first private subnet, min 0 / max 10 instances, secrets from Secret Manager, optional Binary Authorization, deletion protection follows `enable_deletion_protection`. |
| Cloud Run v2 job (instead, with `runtime = "cloud-run-job"`) | `<svc>` | Run to completion, no URL: `job = { task_count, parallelism, max_retries }`, `timeout` is the task timeout. Same runtime SA, secrets, database and Direct VPC egress as a service; `invoker_members` get `run.invoker` on the job (start executions) and the deploy SA `run.developer`. No request alerts or SLO; `enable_unauthenticated` is rejected. |
| SLO (optional `slo`) | `<svc>-<availability\|latency>` | `modules/gcp/monitoring/slo` on a basic `CLOUD_RUN` monitored service `cloud-run-<svc>`: `slo = { goal = 0.999 }` (availability) or `slo = { sli_type = "latency", latency_threshold = "0.5s" }`; `enable_burn_rate_alert = true` pages the `app_alert_notification_channel_ids`. Cloud Run services only. |
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
   gh api orgs/acme --jq .id               # github_repository_owner_id (required)
   ```

3. Create any runtime secrets the service reads in the host project, and set the
   values out of band. Secret values never pass through Terraform or the pipeline:

   ```bash
   gcloud secrets create orders-api-stripe-key --project <host> --replication-policy automatic
   printf '%s' "$STRIPE_KEY" | gcloud secrets versions add orders-api-stripe-key --project <host> --data-file=-
   ```

   (Or declare the secret container with `modules/gcp/data/secret-manager`.)

## Step 2: add the entry (config/landing-zone.yaml)

Add the service under its environment and open a PR:

```yaml
gcp:
  environments:
    dev:
      services:
        orders-api:
          env_vars: {LOG_LEVEL: info}
          secrets:
            STRIPE_API_KEY: {secret: orders-api-stripe-key}
          database: {databases: [orders]}
          github:
            repository_id: "987654321"        # immutable numeric ID
            repository: acme/orders-api       # informational only
            ref: refs/heads/main              # optional: only this ref may deploy
            # environment: dev                # optional: only this GitHub environment
```

The deploy identity also needs two workspace-level settings, which are not
service entries: `enable_app_deploy_wif = true` and
`github_repository_owner_id = "12345678"` (numeric org ID), set as variables on
the `gcp-workload-<env>` workspace.

`config/landing-zone.schema.json` checks the entry's fields (it mirrors the
stage's typed `services` variable). Promoting to the next environment is the same
entry under that environment (see
[`../runbooks/promotion.md`](../runbooks/promotion.md)).

A fully commented version, in tfvars form (the same fields; for a workspace
variable override), is in
[`examples/app-services/dev.app-services.tfvars`](../../examples/app-services/dev.app-services.tfvars).
The typed shape, with every default, is the `services` variable of
[`modules/gcp/stages/app-services`](../../modules/gcp/stages/app-services/README.md).
Common optional fields include `image` (first-revision image; default the
root's `app_bootstrap_image` / `gcp.workload.bootstrap_image`, else
`us-docker.pkg.dev/cloudrun/container/hello`), `ingress`, `cpu`, `memory`,
`min_instances`, `max_instances`, `subnetwork_id`, `invoker_members`,
`enable_unauthenticated`, `enable_binary_authorization` / `binary_authorization_policy`,
`runtime_project_roles` (an escape hatch, empty by default), `artifact_registry`
(cleanup tuning) and `database.{tier,edition,enable_high_availability,encryption_key_name}`.

After merge, Terraform Cloud plans the change and a person approves the apply.
The first apply creates the service with the bootstrap image.

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
Change configuration in `services` in the YAML, not with `gcloud run deploy --set-*` flags.
Terraform would revert those flags on its next apply.

## Exposing the service (front door)

The default ingress is internal only, so callers inside the VPC (and peered
networks) can reach it. To publish a service on your own domain, list it in
`gcp.workload.public_ingress.<env>` in `config/landing-zone.yaml` (or the
`public_ingress_services` variable):

```yaml
gcp:
  workload:
    public_ingress:
      prod:
        orders-api:
          domains: [api.example.com]
          # dns_managed_zone: app-zone   # optional: creates the A record for you
```

`gcp-workload-<env>` then builds, per listed service, a global external
Application Load Balancer (`modules/gcp/network/app-ingress`): a reserved IP, a
serverless NEG to the Cloud Run service, a backend with the environment Cloud
Armor policy (turned on automatically), a Google-managed certificate for the
domains, and an HTTP to HTTPS redirect. The service is switched to
`INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` with `enable_unauthenticated = true`,
unless its entry sets them. `enable_public_ingress = false` turns it off. Point
the domains at `public_ingress["<svc>"].ip_address`. The certificate is issued
only once DNS resolves to that IP.

Unauthenticated invocation turns off the Cloud Run Invoker IAM check on the
service (`invoker_iam_disabled`) instead of binding `allUsers`, so it works under
the gcp-organization domain-restricted-sharing policy
(`iam.allowedPolicyMemberDomains`) with no exception. Exposure stays bounded by
ingress: with `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` the service is reachable only
through the external ALB and its Cloud Armor policy. The older `allUsers` binding is
still available per service via the cloud-run module's
`public_access_mode = "allusers_binding"`. To grant specific callers instead, use
`invoker_members = ["serviceAccount:caller@..."]`.

## GKE Autopilot

`enable_gke_autopilot = true` creates one private Autopilot cluster on the env VPC's
first private subnet (private nodes, private endpoint, Workload Identity, Gateway
API). Workloads and their deploy identity are not generated for GKE yet. Use
[`examples/app-delivery/gke-autopilot-delivery.example.yml`](../../examples/app-delivery/gke-autopilot-delivery.example.yml)
with a deploy SA that you grant `roles/container.clusterViewer` (to fetch credentials) plus a
namespace-scoped Kubernetes `Role` and `RoleBinding`, as the example's header shows. Avoid
project-level `roles/container.developer`: it can read and write every object, Secrets
included, in every cluster in the project.

## AWS golden path (containers)

Implemented in code: add an entry under `aws.workload_environments.<env>.services`
in `config/landing-zone.yaml`. See [AWS](#aws) at the end of this guide.

## What is still your responsibility

- The application's own Postgres grants for its IAM user, and schema migrations.
- Any extra runtime roles (`runtime_project_roles` is empty by default, so keep it
  minimal).
- The content of your domain's DNS zone.
- Choosing service objectives: `slo` creates one per service; pick a goal your error budget can carry.
- Promotion: add the same entry under the next environment in
  `config/landing-zone.yaml` (a new deploy SA and provider are created per
  environment). See
  [`../runbooks/promotion.md`](../runbooks/promotion.md).

## Caveats to validate on real GCP

These items are verified by mocked plan tests only:

- **VPC-SC.** If the env perimeter is enforced and restricts `run`,
  `artifactregistry` or `sqladmin`, add an ingress rule for the app-deploy WIF
  pool (`principalSet://iam.googleapis.com/projects/<host-number>/locations/global/workloadIdentityPools/apps-<env>/*`).
  The default first-revision image `us-docker.pkg.dev/cloudrun/container/hello`
  lives outside the perimeter. Mirror a placeholder into a repo inside it and set
  `gcp.workload.bootstrap_image` in `config/landing-zone.yaml` (or
  `app_bootstrap_image`) once for every service, or `image` per service.
- **Binary Authorization.** The first-revision image must satisfy the policy, or
  the first apply fails. Use an attested image as `bootstrap_image`.
- **Shared repos.** Two services may share one GitHub repository with *different*
  `ref`/`environment` constraints. The provider condition only pins the owner
  (`assertion.repository_owner_id == "<id>"`); each deploy SA is bound to the
  principalSet of its own `(repository_id, ref, environment)` tuple
  (`attribute.repo_ref_env`, `repo_ref`, `repo_env` or `repository_id`), so a
  token reaches only the deploy SA whose constraint it satisfies. A service that
  declares neither `ref` nor `environment` accepts any ref of the repository.
- **Pool IDs.** A WIF pool ID stays reserved for 30 days after deletion. Set
  `app_deploy_wif_pool_id` if you need to re-create a pool sooner.

## AWS

On AWS the golden path is also **implemented in code**, with the same flow: add
one entry under `aws.workload_environments.<env>.services` in
`config/landing-zone.yaml`, open a PR, merge, and approve the apply that
Terraform Cloud queues for `aws-workload-<env>`.
`modules/aws/stages/app-services` (called once from `envs/aws/workload/main.tf`)
creates everything below in that environment's workload account. With no entry
(and `enable_github_oidc = false`) nothing is created. An explicit `services`
workspace variable replaces the config entry.

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

The root also creates a rotating workload CMK `alias/workload-<env>` (always,
unless `kms_key_arn` is supplied). It encrypts ECR, the log groups, Aurora, the
RDS secret, EBS by default and Session Manager.

Shared per environment, created only when `services` is non-empty:

- ECS cluster `<env>-apps` (Container Insights).
- One **internal** ALB `<env>-apps` in the private tier (see
  [Exposing an AWS service](#exposing-an-aws-service) for public modes). Its default action is a
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
- Nothing to create for encryption. With `kms_key_arn = ""` (the default) the
  root creates the workload CMK. Its key policy admits the account root (IAM
  delegation), `logs.<region>.amazonaws.com` (scoped by the `aws:logs:arn`
  encryption context to this account's log groups), ECR via the service, and the
  `<env>-*-exec` task execution roles. To bring your own key, set `kms_key_arn`
  to one with an equivalent policy.
- In the service's GitHub repository, create a GitHub **environment** named after
  the AWS environment (for example `dev`). Protection rules on it, such as
  required reviewers for `prod`, become part of the trust: the deploy role only
  accepts tokens from jobs that run in that environment.

### Step 2: add the entry (AWS, config/landing-zone.yaml)

```yaml
aws:
  workload_environments:
    dev:
      account_key: workload_dev
      services:
        orders:
          container_port: 8080
          cpu: 512
          memory: 1024
          health_check_path: /healthz
          environment: {LOG_LEVEL: info}
          secrets:
            STRIPE_KEY: arn:aws:secretsmanager:eu-west-2:222222222222:secret:orders/stripe-AbCdEf
          # Deploy role trusts ONLY: repo:acme/orders:environment:dev
          github: {repository: acme/orders}
          database: {}   # optional Aurora PostgreSQL
```

`enable_github_oidc = true` (needed for the `github` deploy role) is a
workspace-level variable on `aws-workload-<env>`, not a service field.

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

The first task-definition revision runs `container_image` if set, else the
public placeholder `public.ecr.aws/nginx/nginx-unprivileged:stable-alpine`. It
listens on 8080 (the default `container_port`) and answers 200 on `/`, so the
first apply goes healthy before any pipeline run. Override it for every service
with `aws.workload.bootstrap_image` (or `app_bootstrap_image`), for example a
mirror in reach of a spoke without internet egress. With a different
`container_port`, set `container_image`, or the targets stay unhealthy until
the first deploy (the plan warns). Once a service has a deploy role, the ECS service
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

`app_ingress_mode` (or `aws.workload.app_ingress_mode` in
`config/landing-zone.yaml`) selects the exposure:

| Mode | What you get | Inputs |
|---|---|---|
| `internal` (default) | Internal ALB, reachable from the spoke and, through `app_alb_ingress_cidrs`, from other spokes over the TGW | none |
| `cloudfront_vpc_origin` | The ALB stays internal. CloudFront reaches it through a **VPC origin** (the workload stage attaches an internet gateway with no routes, which VPC origins require) and serves `https://<id>.cloudfront.net` behind a CloudFront WAF (AWS Common + KnownBadInputs). All methods, no caching. | none. Optional `app_edge_domain_name` (ACM certificate in us-east-1, validate via DNS). Leave `app_alb_certificate_arn` unset. |
| `public_alb` | The workload stage adds a `public` subnet tier and an internet gateway. The ALB is internet-facing there on HTTPS (ingress `0.0.0.0/0` unless `app_alb_ingress_cidrs` is set), with a regional WAF (`enable_app_waf`, default on). The org declarative EC2 policy blocks internet-gateway ingress on every VPC (VPC Block Public Access), so this mode also creates a VPC-scoped BPA exclusion for the spoke VPC. | `app_alb_certificate_arn` (required); `allow_vpc_bpa_exclusions = true` in `aws-organization` (otherwise AWS rejects the exclusion and the ALB gets no traffic) |

`app_endpoint` outputs the resulting base URL. Tasks always stay in the private
tier with no public IP.

### Caveats to validate on real AWS

These items are verified by mocked plan tests only:

- **CloudFront VPC origin.** The first VPC origin in an account creates the
  `CloudFront-VPCOrigins-Service-SG` security group. The ALB admits the spoke
  CIDR, which covers the VPC-origin ENIs. Tighten it to that security group if
  you need to.
- **KMS key policy.** The created CMK's policy is asserted in mocked tests only.
  A brought-your-own key must admit CloudWatch Logs, or log group creation
  fails.
- **Egress.** Tasks reach ECR, Logs and Secrets Manager over HTTPS through the
  TGW default route to central egress. If the hub does not provide internet
  egress, add interface endpoints (`ecr.api`, `ecr.dkr`, `logs`,
  `secretsmanager`) to the spoke. S3 (for ECR layers) already has a gateway
  endpoint.
- **Placeholder image.** The default first-revision image is pulled from ECR
  Public, so the spoke needs internet egress (the hub's central egress). A
  standalone spoke (`enable_network_hub = false`) has none, and its private ECR
  pulls also need the interface endpoints above.
- **Database credentials.** The app receives the RDS **master** credentials.
  Create a least-privilege application role (or use IAM database auth, which is
  enabled) and switch `secrets` to it before production.
- **Deletion guard.** Removing a service that has a `database` fails the plan.
  `rds-aurora`'s `terraform_data` deletion guard and AWS deletion protection
  must be removed deliberately first.
- **One OIDC provider per account.** If the account already has a
  `token.actions.githubusercontent.com` provider, the create fails with
  `EntityAlreadyExists`. Use `create_github_oidc_provider = false`.
