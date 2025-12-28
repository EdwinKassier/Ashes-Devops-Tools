terraform {
  backend "gcs" {
    # The bucket name will be provided at init time via -backend-config="bucket=..."
    prefix = "envs/dev"
  }
}
