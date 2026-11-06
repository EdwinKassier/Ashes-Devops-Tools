package terraform.policies.destroy_guard_test

import rego.v1

import data.terraform.policies.destroy_guard as p

one(type, actions, before) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "before": before, "after": null},
}]}}

test_kms_key_delete_flags if {
	count(p.deny) == 1 with input as one("aws_kms_key", ["delete"], {})
}

test_crypto_key_replace_flags_as_replace if {
	some msg in p.deny with input as one("google_kms_crypto_key", ["delete", "create"], {})
	contains(msg, "replaces")
}

test_org_policy_delete_flags if {
	count(p.deny) == 1 with input as one("google_org_policy_policy", ["delete"], {})
}

test_log_bucket_delete_flags if {
	count(p.deny) == 1 with input as one("aws_s3_bucket", ["delete"], {"bucket": "acme-cloudtrail-logs"})
}

test_regular_bucket_delete_passes if {
	count(p.deny) == 0 with input as one("aws_s3_bucket", ["delete"], {"bucket": "acme-website-assets"})
}

test_protected_update_passes if {
	count(p.deny) == 0 with input as one("aws_kms_key", ["update"], {})
}

test_unprotected_delete_passes if {
	count(p.deny) == 0 with input as one("aws_instance", ["delete"], {})
}
