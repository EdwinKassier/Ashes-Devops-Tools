package terraform.policies.gcs_no_public_buckets_test

import rego.v1

import data.terraform.policies.gcs_no_public_buckets as p

bucket(after) := {"plan": {"resource_changes": [{
	"address": "google_storage_bucket.b",
	"mode": "managed",
	"type": "google_storage_bucket",
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

test_private_bucket_passes if {
	count(p.deny) == 0 with input as bucket({"public_access_prevention": "enforced", "uniform_bucket_level_access": true})
}

test_inherited_pap_fails if {
	count(p.deny) == 1 with input as bucket({"public_access_prevention": "inherited", "uniform_bucket_level_access": true})
}

test_missing_settings_fail_twice if {
	count(p.deny) == 2 with input as bucket({})
}

test_ubla_false_fails if {
	some msg in p.deny with input as bucket({"public_access_prevention": "enforced", "uniform_bucket_level_access": false})
	contains(msg, "uniform_bucket_level_access")
}

test_deleted_bucket_ignored if {
	plan := {"plan": {"resource_changes": [{
		"address": "google_storage_bucket.b",
		"mode": "managed",
		"type": "google_storage_bucket",
		"change": {"actions": ["delete"], "before": {}, "after": null},
	}]}}
	count(p.deny) == 0 with input as plan
}
