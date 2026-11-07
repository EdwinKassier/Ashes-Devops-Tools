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

test_google_tags_tag_value_update_allowed if count(p.deny) == 0 with input as one("google_tags_tag_value", ["update"])
