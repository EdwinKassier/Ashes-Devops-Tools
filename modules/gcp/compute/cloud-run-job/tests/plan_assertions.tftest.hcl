# Resource-assertion tests for the cloud-run-job module.
# Proves the module plans a Cloud Run v2 job with the expected, secure-by-default
# attributes. All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id            = "mock-project-id"
  location              = "europe-west1"
  name                  = "mock-job"
  image                 = "europe-west1-docker.pkg.dev/mock-project-id/apps/job:1.0.0"
  service_account_email = "job-sa@mock-project-id.iam.gserviceaccount.com"
}

run "job_plans_with_secure_defaults" {
  command = plan

  variables {
    secret_env_vars = [
      { name = "DATABASE_URL", secret = "database-url" },
    ]
  }

  assert {
    condition     = google_cloud_run_v2_job.this.name == "mock-job" && google_cloud_run_v2_job.this.location == "europe-west1"
    error_message = "job name and location must match the inputs."
  }

  assert {
    condition     = google_cloud_run_v2_job.this.deletion_protection == true
    error_message = "deletion protection must default to on."
  }

  assert {
    condition     = google_cloud_run_v2_job.this.template[0].template[0].service_account == "job-sa@mock-project-id.iam.gserviceaccount.com"
    error_message = "the job must run as the supplied dedicated service account."
  }

  assert {
    condition     = google_cloud_run_v2_job.this.template[0].task_count == 1 && google_cloud_run_v2_job.this.template[0].template[0].max_retries == 3 && google_cloud_run_v2_job.this.template[0].template[0].timeout == "600s"
    error_message = "defaults must be one task, three retries and a 600s task timeout."
  }

  assert {
    condition = one([
      for e in google_cloud_run_v2_job.this.template[0].template[0].containers[0].env : "${e.value_source[0].secret_key_ref[0].secret}@${e.value_source[0].secret_key_ref[0].version}" if e.name == "DATABASE_URL"
    ]) == "database-url@latest"
    error_message = "secret env vars must come from Secret Manager via secret_key_ref."
  }

  assert {
    condition     = length(google_cloud_run_v2_job.this.binary_authorization) == 0 && length(google_cloud_run_v2_job.this.template[0].template[0].vpc_access) == 0
    error_message = "Binary Authorization and VPC egress must be off by default."
  }
}

run "job_direct_vpc_egress_and_binauthz" {
  command = plan

  variables {
    task_count  = 4
    parallelism = 2
    vpc_access = {
      egress = "ALL_TRAFFIC"
      network_interfaces = {
        network    = "projects/host/global/networks/vpc"
        subnetwork = "projects/host/regions/europe-west1/subnetworks/private"
      }
    }
    binary_authorization       = {}
    enable_deletion_protection = false
    env_vars                   = { MODE = "batch" }
  }

  assert {
    condition     = google_cloud_run_v2_job.this.template[0].task_count == 4 && google_cloud_run_v2_job.this.template[0].parallelism == 2
    error_message = "task_count and parallelism must pass through."
  }

  assert {
    condition     = google_cloud_run_v2_job.this.template[0].template[0].vpc_access[0].egress == "ALL_TRAFFIC" && google_cloud_run_v2_job.this.template[0].template[0].vpc_access[0].network_interfaces[0].subnetwork == "projects/host/regions/europe-west1/subnetworks/private"
    error_message = "Direct VPC egress must attach the supplied subnet."
  }

  assert {
    condition     = google_cloud_run_v2_job.this.binary_authorization[0].use_default == true
    error_message = "binary_authorization = {} must enforce the project default policy."
  }

  assert {
    condition     = google_cloud_run_v2_job.this.deletion_protection == false
    error_message = "enable_deletion_protection = false must turn the guard off."
  }

  assert {
    condition     = one([for e in google_cloud_run_v2_job.this.template[0].template[0].containers[0].env : e.value if e.name == "MODE"]) == "batch"
    error_message = "plain env vars must pass through."
  }
}
