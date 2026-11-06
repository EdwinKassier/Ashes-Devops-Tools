# Regression test for budget_filter.projects formatting.
# The Budget API requires each entry in budget_filter.projects to be in
# projects/<id> form; bare project IDs are rejected/ignored.

mock_provider "google" {}

variables {
  billing_account      = "012345-6789AB-CDEF01"
  project_id           = "mock-project"
  project_name         = "mock-project"
  monthly_budget_limit = 500
  region               = "europe-west1"
  projects             = ["proj-a", "proj-b"]
}

run "budget_filter_projects_are_prefixed" {
  command = plan

  assert {
    condition = length(google_billing_budget.monthly_budget.budget_filter[0].projects) > 0 && alltrue([
      for p in google_billing_budget.monthly_budget.budget_filter[0].projects :
      startswith(p, "projects/")
    ])
    error_message = "budget_filter.projects entries must be in projects/<id> form and at least one must be planned"
  }
}

# --- Behavioural plan assertions (derived names, thresholds, labels, toggles) --

run "budget_thresholds_and_derived_names" {
  command = plan

  variables {
    labels = { team = "finops", managed-by = "override" }
  }

  assert {
    condition     = google_billing_budget.monthly_budget.budget_filter[0].projects == toset(["projects/proj-a", "projects/proj-b"])
    error_message = "Each project ID must be rendered as projects/<id>."
  }

  assert {
    condition     = google_billing_budget.monthly_budget.display_name == "mock-project-monthly-budget"
    error_message = "Budget display name must be derived as <project_name>-monthly-budget."
  }

  assert {
    condition     = google_billing_budget.monthly_budget.budget_filter[0].credit_types_treatment == "INCLUDE_ALL_CREDITS"
    error_message = "Budget must include all credits."
  }

  assert {
    condition     = google_billing_budget.monthly_budget.amount[0].specified_amount[0].units == "500" && google_billing_budget.monthly_budget.amount[0].specified_amount[0].currency_code == "USD"
    error_message = "Budget amount must be the stringified monthly_budget_limit in USD (default currency)."
  }

  assert {
    condition     = length(google_billing_budget.monthly_budget.threshold_rules) == 4
    error_message = "Budget must define four threshold rules (alert %, 90%, 100% forecasted, 100% actual)."
  }

  assert {
    condition = [for r in google_billing_budget.monthly_budget.threshold_rules : "${r.threshold_percent}/${r.spend_basis}"] == [
      "0.5/CURRENT_SPEND", "0.9/CURRENT_SPEND", "1/FORECASTED_SPEND", "1/CURRENT_SPEND",
    ]
    error_message = "Threshold rules must be 50% (default) / 90% / 100% forecasted / 100% actual."
  }

  assert {
    condition     = google_billing_budget.monthly_budget.all_updates_rule[0].schema_version == "1.0"
    error_message = "Budget notifications must use schema_version 1.0."
  }

  assert {
    condition     = google_pubsub_topic.budget_alerts.name == "mock-project-budget-alerts"
    error_message = "Alert topic name must be derived as <project_name>-budget-alerts."
  }

  assert {
    condition     = google_pubsub_topic.budget_alerts.labels == tomap({ purpose = "billing-alerts", managed-by = "override", team = "finops" })
    error_message = "Caller labels must merge over the module's default purpose/managed-by labels."
  }

  assert {
    condition     = google_pubsub_subscription.budget_alerts_sub.name == "mock-project-budget-alerts-sub" && google_pubsub_subscription.budget_alerts_sub.topic == "mock-project-budget-alerts"
    error_message = "Subscription must be derived as <project_name>-budget-alerts-sub and attach to the alert topic."
  }

  assert {
    condition     = google_pubsub_subscription.budget_alerts_sub.message_retention_duration == "86400s" && google_pubsub_subscription.budget_alerts_sub.retain_acked_messages == false && google_pubsub_subscription.budget_alerts_sub.ack_deadline_seconds == 20
    error_message = "Subscription must retain unacked messages for 1 day, drop acked messages, and use a 20s ack deadline."
  }

  assert {
    condition     = length(google_pubsub_subscription.budget_alerts_sub.push_config) == 0
    error_message = "Subscription must be pull-only when no webhook_endpoint is supplied."
  }

  assert {
    condition     = length(google_cloudfunctions2_function.budget_notifier) == 0 && length(google_cloud_run_v2_service_iam_member.budget_notifier_invoker) == 0
    error_message = "Email notifier function and invoker IAM must be absent by default."
  }
}

run "all_projects_when_list_empty" {
  command = plan

  variables {
    projects                = []
    alert_threshold_percent = 0.75
  }

  assert {
    condition     = google_billing_budget.monthly_budget.budget_filter[0].projects == null || length(google_billing_budget.monthly_budget.budget_filter[0].projects) == 0
    error_message = "An empty projects list must leave the budget scoped to the whole billing account."
  }

  assert {
    condition     = google_billing_budget.monthly_budget.threshold_rules[0].threshold_percent == 0.75
    error_message = "alert_threshold_percent must drive the first threshold rule."
  }
}

run "webhook_push_and_email_notifier" {
  command = plan

  variables {
    webhook_endpoint           = "https://hooks.example.com/budget"
    webhook_service_account    = "pusher@mock-project.iam.gserviceaccount.com"
    enable_email_notifications = true
    functions_bucket           = "mock-fn-bucket"
    function_source_object     = "notifier.zip"
    email_recipients           = ["a@example.com", "b@example.com"]
    pubsub_service_account     = "service-123@gcp-sa-pubsub.iam.gserviceaccount.com"
    vpc_connector              = "projects/mock-project/locations/europe-west1/connectors/c1"
  }

  assert {
    condition     = google_pubsub_subscription.budget_alerts_sub.push_config[0].push_endpoint == "https://hooks.example.com/budget"
    error_message = "webhook_endpoint must render a push_config."
  }

  assert {
    condition     = google_pubsub_subscription.budget_alerts_sub.push_config[0].oidc_token[0].service_account_email == "pusher@mock-project.iam.gserviceaccount.com"
    error_message = "webhook_service_account must render an OIDC token on the push config."
  }

  assert {
    condition     = google_cloudfunctions2_function.budget_notifier[0].name == "mock-project-budget-notifier" && google_cloudfunctions2_function.budget_notifier[0].build_config[0].runtime == "python312"
    error_message = "Notifier must be a gen2 python312 function named <project_name>-budget-notifier."
  }

  assert {
    condition     = google_cloudfunctions2_function.budget_notifier[0].service_config[0].environment_variables["RECIPIENTS"] == "a@example.com,b@example.com"
    error_message = "RECIPIENTS env var must be the comma-joined email_recipients."
  }

  assert {
    condition     = google_cloudfunctions2_function.budget_notifier[0].service_config[0].vpc_connector_egress_settings == "PRIVATE_RANGES_ONLY"
    error_message = "Supplying a VPC connector must restrict egress to PRIVATE_RANGES_ONLY."
  }

  assert {
    condition     = google_cloudfunctions2_function.budget_notifier[0].event_trigger[0].event_type == "google.cloud.pubsub.topic.v1.messagePublished" && google_cloudfunctions2_function.budget_notifier[0].event_trigger[0].retry_policy == "RETRY_POLICY_RETRY"
    error_message = "Notifier must trigger on Pub/Sub publish with retries."
  }

  assert {
    condition     = google_cloudfunctions2_function.budget_notifier[0].labels["purpose"] == "billing-notifications"
    error_message = "Notifier must carry the billing-notifications purpose label."
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.budget_notifier_invoker[0].role == "roles/run.invoker" && google_cloud_run_v2_service_iam_member.budget_notifier_invoker[0].member == "serviceAccount:service-123@gcp-sa-pubsub.iam.gserviceaccount.com"
    error_message = "Invoker binding must grant roles/run.invoker to the Pub/Sub service agent (serviceAccount: prefixed)."
  }
}
