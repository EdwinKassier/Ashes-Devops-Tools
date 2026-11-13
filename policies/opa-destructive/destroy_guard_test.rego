package terraform.policies.destroy_guard_test

import rego.v1

import data.terraform.policies.destroy_guard as p

one(type, actions) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "after": null},
}]}}

denied_delete(type) if count(p.deny) == 1 with input as one(type, ["delete"])

# ── Every stateful type: a plain delete is denied ──────────────────────────
# GCP
test_google_sql_database_instance_delete_denied if denied_delete("google_sql_database_instance")

test_google_storage_bucket_delete_denied if denied_delete("google_storage_bucket")

test_google_kms_crypto_key_delete_denied if denied_delete("google_kms_crypto_key")

test_google_project_delete_denied if denied_delete("google_project")

test_google_folder_delete_denied if denied_delete("google_folder")

test_google_compute_network_delete_denied if denied_delete("google_compute_network")

test_google_logging_organization_sink_delete_denied if denied_delete("google_logging_organization_sink")

test_google_logging_project_bucket_config_delete_denied if denied_delete("google_logging_project_bucket_config")

test_google_secret_manager_secret_delete_denied if denied_delete("google_secret_manager_secret")

# AWS
test_aws_s3_bucket_delete_denied if denied_delete("aws_s3_bucket")

test_aws_rds_cluster_delete_denied if denied_delete("aws_rds_cluster")

test_aws_db_instance_delete_denied if denied_delete("aws_db_instance")

test_aws_kms_key_delete_denied if denied_delete("aws_kms_key")

test_aws_organizations_account_delete_denied if denied_delete("aws_organizations_account")

test_aws_dynamodb_table_delete_denied if denied_delete("aws_dynamodb_table")

test_aws_vpc_delete_denied if denied_delete("aws_vpc")

test_aws_cloudtrail_delete_denied if denied_delete("aws_cloudtrail")

test_aws_secretsmanager_secret_delete_denied if denied_delete("aws_secretsmanager_secret")

test_aws_cloudformation_stack_set_instance_delete_denied if denied_delete("aws_cloudformation_stack_set_instance")

# Supabase
test_supabase_project_delete_denied if denied_delete("supabase_project")

# ── Control-plane types kept from the advisory list ────────────────────────
test_org_policy_delete_denied if denied_delete("google_org_policy_policy")

test_kms_key_ring_delete_denied if denied_delete("google_kms_key_ring")

# ── Replace is a delete too ────────────────────────────────────────────────
test_crypto_key_replace_denied_as_replace if {
	some msg in p.deny with input as one("google_kms_crypto_key", ["delete", "create"])
	contains(msg, "replaces")
}

test_create_before_destroy_replace_denied if {
	count(p.deny) == 1 with input as one("aws_db_instance", ["create", "delete"])
}

# ── Routine actions pass ───────────────────────────────────────────────────
test_stateful_update_passes if {
	count(p.deny) == 0 with input as one("aws_kms_key", ["update"])
}

test_stateful_create_passes if {
	count(p.deny) == 0 with input as one("google_project", ["create"])
}

test_stateful_noop_passes if {
	count(p.deny) == 0 with input as one("aws_s3_bucket", ["no-op"])
}

test_unprotected_delete_passes if {
	count(p.deny) == 0 with input as one("aws_instance", ["delete"])
}

test_data_source_ignored if {
	count(p.deny) == 0 with input as {"plan": {"resource_changes": [{
		"address": "data.aws_s3_bucket.x",
		"mode": "data",
		"type": "aws_s3_bucket",
		"change": {"actions": ["delete"]},
	}]}}
}

# ── Scrubbed plan (policies/opa/tests/fixtures/scrub.jq output shape) ──────
# A routine upgrade plan: creates, in-place updates, no-ops and a delete of a
# non-stateful type. Synthetic until the first green sandbox apply provides a
# real scrubbed plan (scrub.jq keeps address/mode/type/name and
# change.{actions,after,after_unknown}; it drops before, after_sensitive and IDs).
scrubbed_plan := {"plan": {
	"format_version": "1.2",
	"resource_changes": [
		{
			"address": "module.org.google_kms_crypto_key.state",
			"mode": "managed",
			"type": "google_kms_crypto_key",
			"name": "state",
			"change": {"actions": ["update"], "after": {"rotation_period": "7776000s"}, "after_unknown": {}},
		},
		{
			"address": "module.audit.google_storage_bucket.logs",
			"mode": "managed",
			"type": "google_storage_bucket",
			"name": "logs",
			"change": {"actions": ["no-op"], "after": {"location": "EU"}, "after_unknown": {}},
		},
		{
			"address": "module.net.aws_vpc.this",
			"mode": "managed",
			"type": "aws_vpc",
			"name": "this",
			"change": {"actions": ["update"], "after": {"enable_dns_support": true}, "after_unknown": {}},
		},
		{
			"address": "module.net.aws_route.default",
			"mode": "managed",
			"type": "aws_route",
			"name": "default",
			"change": {"actions": ["delete", "create"], "after": {}, "after_unknown": {}},
		},
		{
			"address": "module.sec.aws_cloudformation_stack_set_instance.config[\"eu-west-1\"]",
			"mode": "managed",
			"type": "aws_cloudformation_stack_set_instance",
			"name": "config",
			"change": {"actions": ["create"], "after": {"stack_set_instance_region": "eu-west-1"}, "after_unknown": {}},
		},
		{
			"address": "data.google_project.current",
			"mode": "data",
			"type": "google_project",
			"name": "current",
			"change": {"actions": ["read"], "after": {}, "after_unknown": {}},
		},
	],
}}

test_scrubbed_real_plan_has_no_denies if {
	count(p.deny) == 0 with input as scrubbed_plan
}

# ── Admin containment (deny policies and the tags they match) ──────────────
test_google_iam_deny_policy_delete_denied if denied_delete("google_iam_deny_policy")

test_google_tags_tag_key_delete_denied if denied_delete("google_tags_tag_key")

test_google_tags_tag_value_delete_denied if denied_delete("google_tags_tag_value")

test_google_iam_deny_policy_replace_denied if count(p.deny) == 1 with input as one("google_iam_deny_policy", ["delete", "create"])

test_google_tags_tag_binding_delete_denied if denied_delete("google_tags_tag_binding")

test_google_tags_location_tag_binding_delete_denied if denied_delete("google_tags_location_tag_binding")

test_tgw_attachment_delete_denied if denied_delete("aws_ec2_transit_gateway_vpc_attachment")

test_tgw_attachment_accepter_delete_denied if denied_delete("aws_ec2_transit_gateway_vpc_attachment_accepter")

test_google_tags_tag_value_update_allowed if count(p.deny) == 0 with input as one("google_tags_tag_value", ["update"])

# ── Backups, locks, data and artefact stores, DNS zones ────────────────────
test_aws_backup_vault_delete_denied if denied_delete("aws_backup_vault")

test_aws_backup_vault_lock_configuration_delete_denied if denied_delete("aws_backup_vault_lock_configuration")

test_aws_s3_bucket_object_lock_configuration_delete_denied if denied_delete("aws_s3_bucket_object_lock_configuration")

test_aws_efs_file_system_delete_denied if denied_delete("aws_efs_file_system")

test_google_bigquery_dataset_delete_denied if denied_delete("google_bigquery_dataset")

test_aws_ecr_repository_delete_denied if denied_delete("aws_ecr_repository")

test_google_artifact_registry_repository_delete_denied if denied_delete("google_artifact_registry_repository")

test_aws_route53_zone_delete_denied if denied_delete("aws_route53_zone")

test_google_dns_managed_zone_delete_denied if denied_delete("google_dns_managed_zone")

test_backup_vault_replace_denied if count(p.deny) == 1 with input as one("aws_backup_vault", ["delete", "create"])

test_dns_zone_create_before_destroy_replace_denied if count(p.deny) == 1 with input as one("aws_route53_zone", ["create", "delete"])

test_backup_vault_update_allowed if count(p.deny) == 0 with input as one("aws_backup_vault", ["update"])

# ── Clusters, databases, caches and backup plans (CICD-8) ──────────────────
test_google_container_cluster_delete_denied if denied_delete("google_container_cluster")

test_google_spanner_instance_delete_denied if denied_delete("google_spanner_instance")

test_google_spanner_database_delete_denied if denied_delete("google_spanner_database")

test_google_bigtable_instance_delete_denied if denied_delete("google_bigtable_instance")

test_google_filestore_instance_delete_denied if denied_delete("google_filestore_instance")

test_google_sql_database_delete_denied if denied_delete("google_sql_database")

test_aws_rds_global_cluster_delete_denied if denied_delete("aws_rds_global_cluster")

test_aws_elasticache_replication_group_delete_denied if denied_delete("aws_elasticache_replication_group")

test_aws_elasticache_cluster_delete_denied if denied_delete("aws_elasticache_cluster")

test_aws_backup_plan_delete_denied if denied_delete("aws_backup_plan")

test_aws_backup_selection_delete_denied if denied_delete("aws_backup_selection")

test_container_cluster_replace_denied if count(p.deny) == 1 with input as one("google_container_cluster", ["delete", "create"])

test_backup_plan_update_allowed if count(p.deny) == 0 with input as one("aws_backup_plan", ["update"])

# ── Turning deletion protection off in place (CICD-8) ──────────────────────
# One resource change with before/after values; after_unknown is optional.
upd(type, actions, before, after, unknown) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "before": before, "after": after, "after_unknown": unknown},
}]}}

protection_off_denied(type, attr, on, off) if {
	some msg in p.deny with input as upd(type, ["update"], {attr: on}, {attr: off}, {})
	contains(msg, attr)
	contains(msg, "turns off")
}

# Boolean switches, one per attribute name in the provider schemas
# (hashicorp/aws 6.x, hashicorp/google 8.x).
test_deletion_protection_off_rds_denied if protection_off_denied("aws_rds_cluster", "deletion_protection", true, false)

test_deletion_protection_off_gke_denied if protection_off_denied("google_container_cluster", "deletion_protection", true, false)

test_deletion_protection_off_sql_instance_denied if protection_off_denied("google_sql_database_instance", "deletion_protection", true, false)

test_deletion_protection_off_rds_global_denied if protection_off_denied("aws_rds_global_cluster", "deletion_protection", true, false)

test_deletion_protection_off_spanner_db_denied if protection_off_denied("google_spanner_database", "deletion_protection", true, false)

test_drop_protection_off_spanner_db_denied if protection_off_denied("google_spanner_database", "enable_drop_protection", true, false)

test_deletion_protection_off_bigtable_denied if protection_off_denied("google_bigtable_instance", "deletion_protection", true, false)

test_deletion_protection_enabled_off_dynamodb_denied if protection_off_denied("aws_dynamodb_table", "deletion_protection_enabled", true, false)

test_deletion_protection_enabled_off_filestore_denied if protection_off_denied("google_filestore_instance", "deletion_protection_enabled", true, false)

test_enable_deletion_protection_off_lb_denied if protection_off_denied("aws_lb", "enable_deletion_protection", true, false)

test_delete_protection_off_network_firewall_denied if protection_off_denied("aws_networkfirewall_firewall", "delete_protection", true, false)

test_termination_protection_off_event_data_store_denied if protection_off_denied("aws_cloudtrail_event_data_store", "termination_protection_enabled", true, false)

# String switches.
test_deletion_policy_prevent_to_delete_denied if protection_off_denied("google_project", "deletion_policy", "PREVENT", "DELETE")

test_deletion_policy_prevent_to_abandon_denied if protection_off_denied("google_project", "deletion_policy", "PREVENT", "ABANDON")

test_cognito_deletion_protection_inactive_denied if protection_off_denied("aws_cognito_user_pool", "deletion_protection", "ACTIVE", "INACTIVE")

test_bigtable_table_unprotected_denied if protection_off_denied("google_bigtable_table", "deletion_protection", "PROTECTED", "UNPROTECTED")

test_firestore_delete_protection_disabled_denied if protection_off_denied("google_firestore_database", "delete_protection_state", "DELETE_PROTECTION_ENABLED", "DELETE_PROTECTION_DISABLED")

# Nested: google_sql_database_instance settings[0].deletion_protection_enabled.
test_sql_settings_deletion_protection_off_denied if {
	some msg in p.deny with input as upd(
		"google_sql_database_instance", ["update"],
		{"settings": [{"deletion_protection_enabled": true, "tier": "db-custom-1-3840"}]},
		{"settings": [{"deletion_protection_enabled": false, "tier": "db-custom-1-3840"}]},
		{},
	)
	contains(msg, "settings.deletion_protection_enabled")
}

test_sql_settings_deletion_protection_kept_passes if {
	count(p.deny) == 0 with input as upd(
		"google_sql_database_instance", ["update"],
		{"settings": [{"deletion_protection_enabled": true, "tier": "db-custom-1-3840"}]},
		{"settings": [{"deletion_protection_enabled": true, "tier": "db-custom-2-7680"}]},
		{},
	)
}

# An unknown planned value cannot be checked, so it counts as turning it off.
test_deletion_protection_unknown_denied if {
	count(p.deny) == 1 with input as upd("aws_rds_cluster", ["update"], {"deletion_protection": true}, {}, {"deletion_protection": true})
}

# Removing the attribute (null after) also turns protection off.
test_deletion_protection_null_after_denied if {
	count(p.deny) == 1 with input as upd("aws_lb", ["update"], {"enable_deletion_protection": true}, {"enable_deletion_protection": null}, {})
}

# Routine changes pass.
test_deletion_protection_on_passes if {
	count(p.deny) == 0 with input as upd("aws_rds_cluster", ["update"], {"deletion_protection": false}, {"deletion_protection": true}, {})
}

test_deletion_protection_kept_passes if {
	count(p.deny) == 0 with input as upd("aws_rds_cluster", ["update"], {"deletion_protection": true, "engine_version": "16.4"}, {"deletion_protection": true, "engine_version": "16.6"}, {})
}

test_deletion_protection_already_off_passes if {
	count(p.deny) == 0 with input as upd("aws_lb", ["update"], {"enable_deletion_protection": false}, {"enable_deletion_protection": false}, {})
}

test_create_without_protection_passes if {
	count(p.deny) == 0 with input as upd("aws_lb", ["create"], null, {"enable_deletion_protection": false}, {})
}

test_deletion_policy_delete_to_abandon_passes if {
	count(p.deny) == 0 with input as upd("google_project", ["update"], {"deletion_policy": "DELETE"}, {"deletion_policy": "ABANDON"}, {})
}

test_noop_with_protection_off_passes if {
	count(p.deny) == 0 with input as upd("aws_rds_cluster", ["no-op"], {"deletion_protection": false}, {"deletion_protection": false}, {})
}
