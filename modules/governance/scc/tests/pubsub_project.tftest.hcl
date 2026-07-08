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
