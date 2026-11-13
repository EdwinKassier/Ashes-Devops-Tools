# Key allowlists of the untyped (type = any) inputs of this root or module. The
# variable validations reject any key outside these lists. Each list must equal
# the attributes of the typed object the value is forwarded to: an extra key
# would be dropped silently by type conversion, and a missing key could not be
# set. scripts/check-any-allowlists.py (make consistency) compares every list
# with the stage type named in scripts/any-allowlists.json.
locals {
  allowed_keys = {
    # modules/gcp/stages/app-services services, plus service_team, which this
    # stage resolves to a service-team project and does not forward.
    app_services = {
      self              = ["service_team", "runtime", "image", "ingress", "cpu", "memory", "min_instances", "health_check_path", "max_instances", "concurrency", "timeout", "env_vars", "secrets", "subnetwork_id", "vpc_egress", "no_proxy", "enable_binary_authorization", "binary_authorization_policy", "enable_unauthenticated", "invoker_members", "runtime_project_roles", "enable_deletion_protection", "labels", "project_id", "project_number", "grant_network_access", "network_access_group", "artifact_registry", "database", "github", "alerts", "job", "slo", "pubsub"]
      artifact_registry = ["immutable_tags", "keep_count", "delete_untagged_older_than", "cleanup_policy_dry_run"]
      database          = ["database_version", "edition", "tier", "databases", "enable_high_availability", "enable_point_in_time_recovery", "backup_location", "transaction_log_retention_days", "encryption_key_name", "enable_deletion_protection"]
      github            = ["repository_id", "repository", "ref", "environment"]
      alerts            = ["enabled", "error_ratio_threshold", "p99_latency_ms", "duration"]
      job               = ["task_count", "parallelism", "max_retries"]
      slo               = ["sli_type", "goal", "rolling_period_days", "latency_threshold", "enable_burn_rate_alert", "burn_rate_threshold", "burn_rate_lookback"]
      pubsub            = ["enabled", "ack_deadline_seconds", "max_delivery_attempts", "message_retention_duration"]
      secrets           = ["secret", "version"]
    }
  }
}
