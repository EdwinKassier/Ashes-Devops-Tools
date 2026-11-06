# MANDATORY: no Cloud Run service may be publicly invokable on its run.app URL.
#   invoker_iam_disabled = true turns off the Invoker IAM check; combined with
#   ingress = INGRESS_TRAFFIC_ALL it exposes an unauthenticated URL with no Cloud
#   Armor that domain-restricted sharing cannot see. Public services must use
#   INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER behind the external ALB.
package terraform.policies.gcp_cloud_run_no_public_url

import rego.v1

import data.terraform.lib

deny contains msg if {
	some rc in lib.written_of_type("google_cloud_run_v2_service")
	lib.after(rc, "invoker_iam_disabled") == true
	lib.after(rc, "ingress") == "INGRESS_TRAFFIC_ALL"
	msg := sprintf("%s: invoker_iam_disabled with ingress INGRESS_TRAFFIC_ALL publishes an unauthenticated run.app URL; use INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER behind the external ALB", [rc.address])
}
