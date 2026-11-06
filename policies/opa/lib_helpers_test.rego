package terraform.lib_test

import rego.v1

import data.terraform.lib

rc(type, actions, after) := {"address": sprintf("%s.this", [type]), "mode": "managed", "type": type, "change": {"actions": actions, "before": null, "after": after, "after_unknown": {}}}

test_managed_excludes_data_sources if {
	plan := {"plan": {"resource_changes": [
		rc("google_storage_bucket", ["create"], {}),
		object.union(rc("google_storage_bucket", ["read"], {}), {"mode": "data"}),
	]}}
	count(lib.managed) == 1 with input as plan
}

test_writes_and_deletes if {
	lib.writes(rc("x", ["create"], {}))
	lib.writes(rc("x", ["update"], {}))
	lib.writes(rc("x", ["delete", "create"], {}))
	not lib.writes(rc("x", ["no-op"], {}))
	not lib.writes(rc("x", ["delete"], {}))
	lib.deletes(rc("x", ["create", "delete"], {}))
}

test_policy_doc_string_and_object if {
	lib.policy_doc(`{"Statement":{"Effect":"Allow"}}`) == {"Statement": {"Effect": "Allow"}}
	lib.statements({"Statement": {"Effect": "Allow"}}) == [{"Effect": "Allow"}]
	lib.statements({"Statement": [{"Effect": "Deny"}]}) == [{"Effect": "Deny"}]
}

test_unknown_values_are_skipped if {
	r := object.union(rc("x", ["create"], {}), {"change": {"after_unknown": {"a": true}}})
	not lib.known_and_not(r, "a", true)
	lib.known_and_not(rc("x", ["create"], {"a": false}), "a", true)
	lib.known_and_not(rc("x", ["create"], {}), "a", true)
}
