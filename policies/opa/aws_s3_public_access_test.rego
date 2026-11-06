package terraform.policies.aws_s3_public_access_test

import rego.v1

import data.terraform.policies.aws_s3_public_access as p

r(type, name, mod, after) := {
	"address": sprintf("%s%s.%s", [mod, type, name]),
	"module_address": mod,
	"mode": "managed",
	"type": type,
	"name": name,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}

plan(rcs) := {"plan": {"resource_changes": rcs}}

full_pab := {"block_public_acls": true, "block_public_policy": true, "ignore_public_acls": true, "restrict_public_buckets": true}

test_private_acl_passes if {
	count(p.deny) == 0 with input as plan([r("aws_s3_bucket_acl", "a", "", {"acl": "private"})])
}

test_public_read_acl_fails if {
	count(p.deny) == 1 with input as plan([r("aws_s3_bucket_acl", "a", "", {"acl": "public-read"})])
}

test_legacy_bucket_acl_fails if {
	count(p.deny) == 1 with input as plan([r("aws_s3_bucket", "b", "", {"acl": "public-read-write"})])
}

test_full_pab_passes if {
	count(p.deny) == 0 with input as plan([r("aws_s3_bucket_public_access_block", "p", "", full_pab)])
}

test_weakened_pab_fails if {
	count(p.deny) == 1 with input as plan([r("aws_s3_bucket_public_access_block", "p", "", object.union(full_pab, {"block_public_policy": false}))])
}

test_weakened_account_pab_fails if {
	count(p.deny) == 1 with input as plan([r("aws_s3_account_public_access_block", "p", "", object.union(full_pab, {"ignore_public_acls": false}))])
}

test_bucket_with_pab_in_module_passes if {
	count(p.warn) == 0 with input as plan([
		r("aws_s3_bucket", "b", "module.logs.", {}),
		r("aws_s3_bucket_public_access_block", "b", "module.logs.", full_pab),
	])
}

test_bucket_without_pab_warns if {
	count(p.warn) == 1 with input as plan([
		r("aws_s3_bucket", "b", "module.logs.", {}),
		r("aws_s3_bucket_public_access_block", "b", "module.other.", full_pab),
	])
}

test_account_pab_satisfies_warn if {
	count(p.warn) == 0 with input as plan([
		r("aws_s3_bucket", "b", "", {}),
		r("aws_s3_account_public_access_block", "acct", "", full_pab),
	])
}
