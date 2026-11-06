package terraform.policies.gcp_cloud_run_no_public_url_test

import rego.v1

import data.terraform.policies.gcp_cloud_run_no_public_url as p

svc(after) := {"plan": {"resource_changes": [{
	"address": "google_cloud_run_v2_service.s",
	"mode": "managed",
	"type": "google_cloud_run_v2_service",
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

test_public_url_denied if {
	count(p.deny) == 1 with input as svc({"invoker_iam_disabled": true, "ingress": "INGRESS_TRAFFIC_ALL"})
}

test_lb_fronted_public_service_allowed if {
	count(p.deny) == 0 with input as svc({"invoker_iam_disabled": true, "ingress": "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"})
}

test_private_service_on_all_ingress_allowed if {
	count(p.deny) == 0 with input as svc({"invoker_iam_disabled": false, "ingress": "INGRESS_TRAFFIC_ALL"})
}

test_deleted_service_ignored if {
	plan := {"plan": {"resource_changes": [{
		"address": "google_cloud_run_v2_service.s",
		"mode": "managed",
		"type": "google_cloud_run_v2_service",
		"change": {"actions": ["delete"], "before": {}, "after": null},
	}]}}
	count(p.deny) == 0 with input as plan
}
