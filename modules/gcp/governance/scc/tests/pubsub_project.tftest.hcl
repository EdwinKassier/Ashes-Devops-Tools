# Regression test for the legacy SCC pubsub publisher IAM member.
# It must set an explicit project so the binding targets var.project_id rather
# than relying on the provider-default project.
# With no notification_configs (the default), the legacy single-config path is
# active and google_pubsub_topic_iam_member.scc_publisher[0] is created.

mock_provider "google" {}

variables {
  org_id     = "123456789"
  project_id = "mock-project"
}

run "legacy_publisher_sets_explicit_project" {
  command = plan

  assert {
    condition     = length(google_pubsub_topic_iam_member.scc_publisher) > 0 && google_pubsub_topic_iam_member.scc_publisher[0].project == var.project_id
    error_message = "legacy scc_publisher IAM member must set project = var.project_id"
  }
}

# --- Behavioural plan assertions (legacy vs multi-config switch, defaults) ----

run "legacy_path_defaults" {
  command = plan

  assert {
    condition     = length(google_pubsub_topic.scc_notifications) == 1 && length(google_scc_notification_config.notification_config) == 1
    error_message = "With no notification_configs, the legacy topic and notification config must be created."
  }

  assert {
    condition     = length(google_pubsub_topic.scc_notifications_multi) == 0 && length(google_scc_notification_config.notification_config_multi) == 0 && length(google_pubsub_topic_iam_member.scc_publisher_multi) == 0
    error_message = "Multi-config resources must be absent on the legacy path."
  }

  assert {
    condition     = google_pubsub_topic.scc_notifications[0].name == "scc-notifications" && google_scc_notification_config.notification_config[0].config_id == "scc-notification-config"
    error_message = "Legacy topic/config must default to scc-notifications / scc-notification-config."
  }

  assert {
    condition     = google_scc_notification_config.notification_config[0].streaming_config[0].filter == "state=\"ACTIVE\""
    error_message = "Legacy streaming filter must default to active findings only."
  }

  assert {
    condition     = google_scc_notification_config.notification_config[0].organization == "123456789"
    error_message = "Notification config must be org-scoped."
  }

  assert {
    condition     = google_pubsub_topic_iam_member.scc_publisher[0].role == "roles/pubsub.publisher" && google_pubsub_topic_iam_member.scc_publisher[0].topic == "scc-notifications"
    error_message = "SCC service agent must be granted only roles/pubsub.publisher on the legacy topic."
  }
}

run "multi_config_takes_precedence" {
  command = plan

  variables {
    kms_key_name = "projects/mock-project/locations/global/keyRings/kr/cryptoKeys/scc"
    notification_configs = {
      critical-high = {
        pubsub_topic_name = "scc-critical"
        filter            = "state=\"ACTIVE\" AND severity=\"CRITICAL\""
      }
      medium-low = {
        pubsub_topic_name = "scc-medium"
        description       = "Medium findings"
        filter            = "state=\"ACTIVE\" AND severity=\"MEDIUM\""
      }
    }
  }

  assert {
    condition     = length(google_pubsub_topic.scc_notifications) == 0 && length(google_scc_notification_config.notification_config) == 0 && length(google_pubsub_topic_iam_member.scc_publisher) == 0
    error_message = "Supplying notification_configs must disable the legacy single-config resources."
  }

  assert {
    condition     = toset(keys(google_scc_notification_config.notification_config_multi)) == toset(["critical-high", "medium-low"])
    error_message = "One notification config must be planned per notification_configs entry."
  }

  assert {
    condition     = alltrue([for k, v in google_scc_notification_config.notification_config_multi : v.config_id == k])
    error_message = "Each multi notification config_id must be its map key."
  }

  assert {
    condition     = google_scc_notification_config.notification_config_multi["critical-high"].description == "SCC notification configuration"
    error_message = "Multi-config description must default when omitted."
  }

  assert {
    condition     = google_pubsub_topic.scc_notifications_multi["medium-low"].labels == tomap({ scc-config = "medium-low", managed-by = "terraform" })
    error_message = "Multi topics must be labelled with their config key and managed-by = terraform."
  }

  assert {
    condition     = alltrue([for t in google_pubsub_topic.scc_notifications_multi : t.kms_key_name == "projects/mock-project/locations/global/keyRings/kr/cryptoKeys/scc"])
    error_message = "kms_key_name must CMEK-encrypt every multi-config topic."
  }

  assert {
    condition     = google_pubsub_topic_iam_member.scc_publisher_multi["critical-high"].topic == "scc-critical" && alltrue([for b in google_pubsub_topic_iam_member.scc_publisher_multi : b.role == "roles/pubsub.publisher" && b.project == "mock-project"])
    error_message = "Each multi topic must get a publisher binding in the module project."
  }
}

run "module_labels_applied" {
  command = plan

  variables {
    labels = { owner = "test" }

  }

  assert {
    condition     = google_pubsub_topic.scc_notifications[0].labels["owner"] == "test"
    error_message = "var.labels must land on the SCC notification topic."
  }
}
