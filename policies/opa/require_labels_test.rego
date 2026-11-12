package terraform.policies.require_labels_test

import rego.v1

import data.terraform.policies.require_labels as p

one(type, after, unknown) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": unknown},
}]}}

gcp_labels := {"managed-by": "terraform", "environment": "prod", "cost-center": "platform", "owner": "platform-team"}

aws_tags := {"ManagedBy": "terraform", "Environment": "prod", "CostCenter": "platform", "Owner": "platform-team"}

test_gcp_with_required_labels_passes if {
	count(p.deny) == 0 with input as one("google_storage_bucket", {"effective_labels": gcp_labels}, {})
}

# Provider default_labels appear in effective_labels only; labels may be null.
test_gcp_default_labels_pass if {
	count(p.deny) == 0 with input as one("google_pubsub_topic", {"labels": null, "effective_labels": gcp_labels}, {})
}

# Resource labels and provider defaults together satisfy the set.
test_gcp_labels_and_effective_labels_combine if {
	count(p.deny) == 0 with input as one("google_kms_crypto_key", {"labels": {"owner": "data-team"}, "effective_labels": object.remove(gcp_labels, ["owner"])}, {})
}

test_gcp_missing_cost_center_fails if {
	count(p.deny) == 1 with input as one("google_storage_bucket", {"effective_labels": object.remove(gcp_labels, ["cost-center"])}, {})
}

test_gcp_missing_label_named_in_message if {
	some msg in p.deny with input as one("google_storage_bucket", {"effective_labels": object.remove(gcp_labels, ["cost-center", "owner"])}, {})
	contains(msg, `["cost-center", "owner"]`)
}

test_unlabelled_gcp_resource_fails if {
	count(p.deny) == 1 with input as one("google_kms_crypto_key", {"labels": {}}, {})
}

# Cloud SQL carries labels in settings[0].user_labels, which provider
# default_labels never fill.
test_cloud_sql_user_labels_pass if {
	count(p.deny) == 0 with input as one("google_sql_database_instance", {"settings": [{"user_labels": gcp_labels}]}, {})
}

test_cloud_sql_without_user_labels_fails if {
	count(p.deny) == 1 with input as one("google_sql_database_instance", {"settings": [{"user_labels": {"environment": "prod"}}]}, {})
}

test_cloud_sql_unknown_user_labels_pass if {
	count(p.deny) == 0 with input as one("google_sql_database_instance", {"settings": [{}]}, {"settings": [{"user_labels": true}]})
}

test_aws_with_required_tags_passes if {
	count(p.deny) == 0 with input as one("aws_s3_bucket", {"tags": null, "tags_all": aws_tags}, {})
}

test_aws_missing_owner_fails if {
	count(p.deny) == 1 with input as one("aws_kms_key", {"tags_all": object.remove(aws_tags, ["Owner"])}, {})
}

test_untagged_aws_resource_fails if {
	count(p.deny) == 1 with input as one("aws_kms_key", {"tags": null, "tags_all": {}}, {})
}

# Key names are case-sensitive: AWS keys are PascalCase, GCP keys lowercase.
test_aws_lowercase_keys_fail if {
	count(p.deny) == 1 with input as one("aws_iam_role", {"tags_all": gcp_labels}, {})
}

test_unknown_tags_still_pass if {
	count(p.deny) == 0 with input as one("aws_vpc", {}, {"tags_all": true})
}

# A known map with an unknown VALUE still has its key.
test_unknown_tag_value_keeps_key if {
	count(p.deny) == 0 with input as one("aws_vpc", {"tags_all": object.remove(aws_tags, ["Owner"])}, {"tags_all": {"Owner": true}})
}

test_untracked_type_ignored if {
	count(p.deny) == 0 with input as one("aws_route", {}, {})
}

test_delete_ignored if {
	count(p.deny) == 0 with input as {"plan": {"resource_changes": [{
		"address": "aws_kms_key.x",
		"mode": "managed",
		"type": "aws_kms_key",
		"change": {"actions": ["delete"], "after": null, "after_unknown": {}},
	}]}}
}
