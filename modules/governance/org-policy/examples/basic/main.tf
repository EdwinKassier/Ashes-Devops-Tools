# Example: apply security-hardening org policies to an environment folder.
# These policies enforce common CIS and Google Cloud security baselines.

locals {
  folder_id = "folders/123456789012"
}

module "security_policies" {
  source = "../../"

  parent = local.folder_id

  boolean_policies = [
    # Require Shielded VM for all new Compute instances.
    { constraint = "compute.requireShieldedVm", enforce = true },
    # Block serial port access (common attack vector).
    { constraint = "compute.disableSerialPortAccess", enforce = true },
    # Block public IP on Cloud SQL instances.
    { constraint = "sql.restrictPublicIp", enforce = true },
    # Prevent public access to Cloud Storage buckets.
    { constraint = "storage.publicAccessPrevention", enforce = true },
    # Require uniform bucket-level access (disables legacy ACLs).
    { constraint = "storage.uniformBucketLevelAccess", enforce = true },
  ]

  list_policies = [
    # Restrict resource creation to approved GCP regions.
    {
      constraint     = "gcp.resourceLocations"
      allow_all      = false
      deny_all       = false
      allowed_values = ["in:us-locations", "in:europe-locations"]
      denied_values  = []
    },
  ]
}
