package terraform.policies.database_private_encrypted_test

import rego.v1

import data.terraform.policies.database_private_encrypted as p

one(type, after) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

sql(ipcs) := one("google_sql_database_instance", {"settings": [{"ip_configuration": ipcs}]})

test_private_cloud_sql_passes if {
	count(p.deny) == 0 with input as sql([{"ipv4_enabled": false, "private_network": "projects/p/global/networks/n"}])
}

test_public_cloud_sql_fails if {
	count(p.deny) == 1 with input as sql([{"ipv4_enabled": true}])
}

test_cloud_sql_without_ip_configuration_fails if {
	count(p.deny) == 1 with input as sql([])
}

test_encrypted_private_rds_passes if {
	count(p.deny) == 0 with input as one("aws_db_instance", {"storage_encrypted": true, "publicly_accessible": false})
}

test_unencrypted_rds_fails if {
	count(p.deny) == 1 with input as one("aws_db_instance", {"storage_encrypted": false, "publicly_accessible": false})
}

test_public_rds_fails if {
	count(p.deny) == 1 with input as one("aws_db_instance", {"storage_encrypted": true, "publicly_accessible": true})
}

test_unencrypted_aurora_cluster_fails if {
	count(p.deny) == 1 with input as one("aws_rds_cluster", {"storage_encrypted": false})
}

test_public_aurora_instance_fails if {
	count(p.deny) == 1 with input as one("aws_rds_cluster_instance", {"publicly_accessible": true})
}

unknown_attr(type, after, attr) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {attr: true}},
}]}}

test_unknown_encryption_denied if {
	count(p.deny) == 1 with input as unknown_attr("aws_rds_cluster", {}, "storage_encrypted")
}

test_unknown_db_instance_encryption_denied if {
	count(p.deny) == 1 with input as unknown_attr("aws_db_instance", {"publicly_accessible": false}, "storage_encrypted")
}

test_unknown_publicly_accessible_denied if {
	count(p.deny) == 1 with input as unknown_attr("aws_rds_cluster_instance", {}, "publicly_accessible")
}

test_private_aurora_instance_passes if {
	count(p.deny) == 0 with input as one("aws_rds_cluster_instance", {"publicly_accessible": false})
}

test_unknown_message_names_plan_known if {
	some msg in p.deny with input as unknown_attr("aws_rds_cluster", {}, "storage_encrypted")
	contains(msg, "plan-known")
}
