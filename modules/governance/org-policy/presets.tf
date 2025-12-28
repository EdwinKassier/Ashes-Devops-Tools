# -----------------------------------------------------------------------------
# Preset Policy Packs
# These locals provide ready-to-use policy configurations for common use cases.
# Import this file and reference locals in your module instantiation.
# -----------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # Preset: Security Hardening (Recommended Baseline)
  # ---------------------------------------------------------------------------
  preset_security_hardening_boolean = [
    { constraint = "sql.restrictPublicIp", enforce = true },
    { constraint = "storage.uniformBucketLevelAccess", enforce = true },
    { constraint = "storage.publicAccessPrevention", enforce = true },
    { constraint = "iam.disableServiceAccountKeyCreation", enforce = true },
    { constraint = "compute.requireShieldedVm", enforce = true },
    { constraint = "compute.disableSerialPortAccess", enforce = true },
    { constraint = "compute.requireOsLogin", enforce = true },
  ]

  # ---------------------------------------------------------------------------
  # Preset: CMEK Encryption Required
  # Denies resource creation without CMEK for specified services
  # ---------------------------------------------------------------------------
  preset_cmek_required_list = [
    {
      constraint     = "gcp.restrictNonCmekServices"
      allow_all      = false
      deny_all       = false
      allowed_values = []
      denied_values = [
        "storage.googleapis.com",
        "bigquery.googleapis.com",
        "sqladmin.googleapis.com",
        "spanner.googleapis.com",
        "pubsub.googleapis.com",
        "secretmanager.googleapis.com",
      ]
    }
  ]

  # ---------------------------------------------------------------------------
  # Preset: Regional Restrictions (Example: US/EU Only)
  # ---------------------------------------------------------------------------
  preset_us_eu_locations_list = [
    {
      constraint     = "gcp.resourceLocations"
      allow_all      = false
      deny_all       = false
      allowed_values = ["in:us-locations", "in:eu-locations"]
      denied_values  = []
    }
  ]

  # ---------------------------------------------------------------------------
  # Preset: Strict Compute Security
  # ---------------------------------------------------------------------------
  preset_compute_security_boolean = [
    { constraint = "compute.requireShieldedVm", enforce = true },
    { constraint = "compute.disableSerialPortAccess", enforce = true },
    { constraint = "compute.disableNestedVirtualization", enforce = true },
    { constraint = "compute.requireOsLogin", enforce = true },
    { constraint = "compute.disableGuestAttributesAccess", enforce = true },
  ]

  # ---------------------------------------------------------------------------
  # Preset: No External IPs (Zero Trust Network)
  # ---------------------------------------------------------------------------
  preset_no_external_ips_list = [
    {
      constraint     = "compute.vmExternalIpAccess"
      allow_all      = false
      deny_all       = true
      allowed_values = []
      denied_values  = []
    }
  ]
}
