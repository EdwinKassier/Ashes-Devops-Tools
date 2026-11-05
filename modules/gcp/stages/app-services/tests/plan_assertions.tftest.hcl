# Plan assertions for the app-services stage (the application golden path).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id     = "acme-dev-host-abcd"
  project_number = "222222222222"
  region         = "europe-west1"
  environment    = "dev"
  network_id     = "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
  subnetwork_id  = "projects/acme-dev-host-abcd/regions/europe-west1/subnetworks/acme-dev-vpc-private-europe-west1-b"
}

# The default (services = {}, every flag off) must create nothing at all.
run "default_creates_nothing" {
  command = plan

  assert {
    condition = (
      length(module.registry) == 0 &&
      length(google_service_account.runtime) == 0 &&
      length(module.service) == 0 &&
      length(module.database) == 0 &&
      length(google_service_account.deploy) == 0 &&
      length(google_iam_workload_identity_pool.apps) == 0 &&
      length(google_iam_workload_identity_pool_provider.github) == 0 &&
      length(module.gke) == 0 &&
      length(google_project_service.this) == 0
    )
    error_message = "with services = {} and every flag off, the stage must create nothing."
  }

  assert {
    condition     = output.workload_identity_provider == null && length(output.services) == 0
    error_message = "outputs must be empty/null by default."
  }
}

# One service with a deploy identity: repo + runtime SA + Cloud Run + deploy SA.
run "one_service_full_golden_path" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    services = {
      api = {
        secrets = { API_KEY = { secret = "api-key" } }
        github  = { repository_id = "123456789", repository = "acme/api" }
      }
    }
  }

  assert {
    condition     = length(module.registry) == 1 && length(google_service_account.runtime) == 1 && length(module.service) == 1 && length(google_service_account.deploy) == 1
    error_message = "one service must create exactly one repo, runtime SA, Cloud Run service and deploy SA."
  }

  assert {
    condition     = length(module.database) == 0
    error_message = "no database may be created unless the service declares one."
  }

  assert {
    condition     = google_service_account.runtime["api"].account_id == "api-run" && google_service_account.deploy["api"].account_id == "api-deploy"
    error_message = "runtime/deploy SA IDs must be <service>-run / <service>-deploy."
  }

  # Ingress is internal by default, and Direct VPC egress lands on the env subnet.
  assert {
    condition     = module.service["api"].ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY"
    error_message = "Cloud Run ingress must default to INGRESS_TRAFFIC_INTERNAL_ONLY."
  }

  assert {
    condition     = output.services["api"].image_repository == "europe-west1-docker.pkg.dev/acme-dev-host-abcd/api/api"
    error_message = "image repository path must be <region>-docker.pkg.dev/<project>/<service>/<service>."
  }

  # WIF binding keys on the IMMUTABLE numeric repository_id, never the name.
  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].member == "principalSet://iam.googleapis.com/projects/222222222222/locations/global/workloadIdentityPools/apps-dev/attribute.repository_id/123456789"
    error_message = "the deploy SA WIF binding must use principalSet .../attribute.repository_id/<id>."
  }

  assert {
    condition     = google_service_account_iam_member.deploy_wif["api"].role == "roles/iam.workloadIdentityUser"
    error_message = "the WIF binding must grant roles/iam.workloadIdentityUser."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_condition == "(assertion.repository_id == \"123456789\")"
    error_message = "the provider must fail closed on the declared repository_id."
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repository_id"] == "assertion.repository_id"
    error_message = "the provider must map attribute.repository_id from the token."
  }

  # Deploy SA: exactly run.developer on the service, writer on the repo, actAs on the runtime SA.
  assert {
    condition     = google_cloud_run_v2_service_iam_member.deploy["api"].role == "roles/run.developer"
    error_message = "the deploy SA must get roles/run.developer on its own service."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.deploy["api"].role == "roles/artifactregistry.writer"
    error_message = "the deploy SA must get roles/artifactregistry.writer on its own repo."
  }

  assert {
    condition     = google_service_account_iam_member.deploy_act_as_runtime["api"].role == "roles/iam.serviceAccountUser" && google_service_account_iam_member.deploy_act_as_runtime["api"].member == "serviceAccount:api-deploy@acme-dev-host-abcd.iam.gserviceaccount.com"
    error_message = "the deploy SA must get serviceAccountUser on the runtime SA only."
  }

  # Least privilege: runtime SA gets secretAccessor on its declared secret and nothing project-wide.
  assert {
    condition     = google_secret_manager_secret_iam_member.runtime["api/API_KEY"].secret_id == "api-key" && google_secret_manager_secret_iam_member.runtime["api/API_KEY"].member == "serviceAccount:api-run@acme-dev-host-abcd.iam.gserviceaccount.com"
    error_message = "the runtime SA must get secretAccessor on exactly the secrets it references."
  }

  assert {
    condition     = length(google_project_iam_member.runtime_extra) == 0 && length(google_project_iam_member.runtime_sql) == 0
    error_message = "the runtime SA must get no project-level roles by default."
  }

  assert {
    condition     = output.github_actions["api"].GCP_WIF_PROVIDER == "projects/222222222222/locations/global/workloadIdentityPools/apps-dev/providers/github"
    error_message = "github_actions must expose the full WIF provider resource name."
  }
}

# Ref / environment constraints narrow the provider condition.
run "github_ref_and_environment_constrain_condition" {
  command = plan

  variables {
    enable_app_deploy_wif      = true
    github_repository_owner_id = "42"
    services = {
      api = {
        github = { repository_id = "123", ref = "refs/heads/main", environment = "dev" }
      }
    }
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_condition == "assertion.repository_owner_id == \"42\" && (assertion.repository_id == \"123\" && assertion.ref == \"refs/heads/main\" && (has(assertion.environment) && assertion.environment == \"dev\"))"
    error_message = "owner, ref and environment constraints must all be ANDed into the provider condition."
  }
}

# Cloud SQL: private IP only, IAM auth, runtime SA as the IAM DB user.
run "database_private_ip_iam_auth" {
  command = plan

  variables {
    services = {
      api = {
        database = { databases = ["orders"] }
      }
    }
  }

  assert {
    condition     = module.database["api"].public_ip_enabled == false
    error_message = "the instance must be private-IP only (no public IPv4)."
  }

  assert {
    condition     = module.database["api"].private_network == "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
    error_message = "the instance must peer into the ENV host VPC (where the host stage creates PSA), not the hub."
  }

  assert {
    condition     = module.database["api"].name == "api-db"
    error_message = "the instance must be named <service>-db."
  }

  assert {
    condition     = output.services["api"].database_iam_user == "api-run@acme-dev-host-abcd.iam"
    error_message = "the runtime SA must be the IAM database user (email minus .gserviceaccount.com)."
  }

  assert {
    condition     = google_project_iam_member.runtime_sql["api/client"].condition[0].expression == "resource.name == \"projects/acme-dev-host-abcd/instances/api-db\""
    error_message = "cloudsql.client must be conditioned to the service's own instance."
  }

  assert {
    condition     = contains(keys(google_project_service.this), "sqladmin.googleapis.com")
    error_message = "declaring a database must enable sqladmin.googleapis.com."
  }
}

run "gke_autopilot_opt_in" {
  command = plan

  variables {
    enable_gke_autopilot = true
  }

  assert {
    condition     = length(module.gke) == 1 && output.gke_cluster_name == "dev-apps"
    error_message = "enable_gke_autopilot must create one cluster named <env>-apps."
  }
}
