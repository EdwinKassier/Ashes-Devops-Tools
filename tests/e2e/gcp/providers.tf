# Real provider: credentials come from Application Default Credentials. In CI
# that is the short-lived token minted by google-github-actions/auth via
# Workload Identity Federation (no service-account keys); locally it is
# `gcloud auth application-default login`.
#
# default_labels stamps every labelable resource with the run id so the
# workflow's always() safety-net step can find and delete anything a failed
# `terraform test` teardown leaves behind.
provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    "e2e-run-id" = var.run_id
    "managed-by" = "terraform-e2e"
  }
}
