package terraform.policies.aws_kms_key_rotation_test

import rego.v1

import data.terraform.policies.aws_kms_key_rotation as p

key(after) := {"plan": {"resource_changes": [{
	"address": "aws_kms_key.k",
	"mode": "managed",
	"type": "aws_kms_key",
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

test_rotating_key_passes if {
	count(p.deny) == 0 with input as key({"enable_key_rotation": true, "customer_master_key_spec": "SYMMETRIC_DEFAULT"})
}

test_non_rotating_key_fails if {
	count(p.deny) == 1 with input as key({"enable_key_rotation": false})
}

test_rotation_omitted_fails if {
	count(p.deny) == 1 with input as key({})
}

test_asymmetric_key_exempt if {
	count(p.deny) == 0 with input as key({"enable_key_rotation": false, "customer_master_key_spec": "RSA_2048"})
}
