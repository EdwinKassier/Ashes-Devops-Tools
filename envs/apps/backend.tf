terraform {
  backend "cloud" {
    # REPLACE WITH YOUR TFC ORGANIZATION NAME
    organization = "example-org-please-update"

    workspaces {
      prefix = "apps-"
    }
  }
}
