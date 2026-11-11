# Plan assertions for the cloud-sql module: verify the instance is planned with the
# secure-by-default posture (private IP only, TLS-only, backups + PITR, IAM auth,
# deletion protection) and that databases/users fan out correctly.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id      = "mock-project"
  region          = "europe-west1"
  name            = "mock-db"
  private_network = "projects/mock-project/global/networks/hub"
}

run "instance_secure_defaults" {
  command = plan

  assert {
    condition     = google_sql_database_instance.this.database_version == "POSTGRES_16"
    error_message = "database_version must default to POSTGRES_16."
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "Instance must have no public IPv4 address."
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].private_network == var.private_network
    error_message = "Instance must be peered into the caller-supplied private network."
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "Instance must reject non-TLS connections (ssl_mode ENCRYPTED_ONLY)."
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].enabled == true
    error_message = "Automated backups must be enabled."
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].point_in_time_recovery_enabled == true
    error_message = "Point-in-time recovery must be on by default."
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].availability_type == "ZONAL"
    error_message = "availability_type must default to ZONAL."
  }

  assert {
    condition     = google_sql_database_instance.this.deletion_protection == true
    error_message = "deletion_protection must be on by default."
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 1
    error_message = "Deletion-protection guard must be created by default."
  }

  assert {
    condition     = anytrue([for f in google_sql_database_instance.this.settings[0].database_flags : f.name == "cloudsql.iam_authentication" && f.value == "on"])
    error_message = "The cloudsql.iam_authentication flag must be present by default."
  }

  # Secure-by-default PostgreSQL logging flags are applied alongside IAM auth.
  assert {
    condition     = anytrue([for f in google_sql_database_instance.this.settings[0].database_flags : f.name == "log_connections" && f.value == "on"])
    error_message = "Secure default log flags (log_connections=on) must be applied by default."
  }

  assert {
    condition     = contains([for f in google_sql_database_instance.this.settings[0].database_flags : f.name], "cloudsql.iam_authentication")
    error_message = "IAM database authentication flag must be wired in by default."
  }
}

run "high_availability_is_regional" {
  command = plan

  variables {
    enable_high_availability = true
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].availability_type == "REGIONAL"
    error_message = "enable_high_availability must set availability_type to REGIONAL."
  }
}

run "cmek_wired_when_provided" {
  command = plan

  variables {
    encryption_key_name = "projects/mock-project/locations/europe-west1/keyRings/kr/cryptoKeys/sql"
  }

  assert {
    condition     = google_sql_database_instance.this.encryption_key_name == var.encryption_key_name
    error_message = "encryption_key_name (CMEK) must be wired through when provided."
  }
}

run "databases_and_users_fan_out" {
  command = plan

  variables {
    databases = ["app", "analytics"]
    users = [
      { name = "app", password = "s3cret-value" },
      { name = "svc@mock-project.iam", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
    ]
  }

  assert {
    condition     = length(google_sql_database.this) == 2
    error_message = "One google_sql_database must be planned per databases entry."
  }

  assert {
    condition     = length(google_sql_user.this) == 2
    error_message = "One google_sql_user must be planned per users entry."
  }
}

# A user flagged ephemeral_password reads its password from the ephemeral
# user_passwords map; the write-only version counter stays plannable.
run "ephemeral_password_user_planned" {
  command = plan

  variables {
    users = [
      { name = "app", ephemeral_password = true, password_version = 3 },
      { name = "legacy", password = "inline-value" },
    ]
    user_passwords = { app = "s3cret-value" }
  }

  assert {
    condition     = length(google_sql_user.this) == 2
    error_message = "Both the ephemeral-password and inline-password users must be planned."
  }

  assert {
    condition     = google_sql_user.this["app"].password_wo_version == 3
    error_message = "password_wo_version must come from the user's password_version for ephemeral_password users."
  }
}

# PostgreSQL 16+ defaults to ENTERPRISE_PLUS, which rejects db-custom-* tiers; the
# module pins ENTERPRISE so the default tier is creatable.
run "edition_defaults_to_enterprise" {
  command = plan

  assert {
    condition     = google_sql_database_instance.this.settings[0].edition == "ENTERPRISE"
    error_message = "edition must default to ENTERPRISE so the default db-custom tier is valid."
  }
}

# Backups default to Cloud SQL's own location; backup_location moves them to
# another region (or multi-region) so they survive a regional outage.
run "backup_location_default_and_cross_region" {
  command = plan

  variables {
    backup_location = "europe-west2"
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].backup_configuration[0].location == "europe-west2" && output.backup_location == "europe-west2"
    error_message = "backup_location must set the automated backups' location."
  }
}

run "backup_location_unset_by_default" {
  command = plan

  assert {
    condition     = output.backup_location == null && output.availability_type == "ZONAL"
    error_message = "By default the backups use Cloud SQL's location and the instance is zonal."
  }
}
