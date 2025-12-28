terraform {
  backend "cloud" {
    # REPLACE WITH YOUR TFC ORGANIZATION NAME
    organization = "example-org-please-update"

    workspaces {
      name = "organization-apps-uat"
    }
  }
}
