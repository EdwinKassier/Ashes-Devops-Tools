# MANDATORY: listed labellable GCP resources and taggable AWS resources carry
# the four ownership and cost keys that every root writes through its provider
# defaults, so billing export, Cost Explorer and asset inventory queries can
# attribute them.
#   - GCP: managed-by, environment, cost-center, owner. Provider default_labels
#     show up in effective_labels, which counts with labels. Cloud SQL keeps its
#     labels in settings[0].user_labels, which default_labels never fill, so
#     the modules set them there explicitly.
#   - AWS: ManagedBy, Environment, CostCenter, Owner in tags or tags_all
#     (tags_all includes provider default_tags).
# Only types that can carry labels or tags are listed; any other type is
# never checked. A computed (unknown) label or tag map is skipped: its keys are
# not plannable. Key names are case-sensitive.
package terraform.policies.require_labels

import rego.v1

import data.terraform.lib

gcp_required := {"managed-by", "environment", "cost-center", "owner"}

aws_required := {"ManagedBy", "Environment", "CostCenter", "Owner"}

# Every type below has a top-level labels and effective_labels attribute in
# hashicorp/google 8.x, except google_sql_database_instance (see above).
gcp_labelled_types := {
	"google_storage_bucket",
	"google_kms_crypto_key",
	"google_pubsub_topic",
	"google_bigquery_dataset",
	"google_compute_instance",
	"google_sql_database_instance",
	"google_cloud_run_v2_service",
	"google_secret_manager_secret",
	"google_artifact_registry_repository",
	"google_project",
}

# Every type below has tags and tags_all in hashicorp/aws 6.x.
aws_tagged_types := {
	"aws_s3_bucket",
	"aws_kms_key",
	"aws_vpc",
	"aws_instance",
	"aws_db_instance",
	"aws_rds_cluster",
	"aws_lb",
	"aws_ecs_service",
	"aws_lambda_function",
	"aws_iam_role",
	"aws_cloudwatch_log_group",
	"aws_secretsmanager_secret",
}

# Planned label or tag maps of a resource, with the matching after_unknown
# entry. A map with an unknown VALUE still has a known key: after omits the
# value and after_unknown names the key.
label_maps(rc) := [[object.get(rc.change.after, attr, null), object.get(rc.change.after_unknown, attr, null)] |
	some attr in ["labels", "effective_labels"]
] if rc.type != "google_sql_database_instance"

label_maps(rc) := [[object.get(s, "user_labels", null), object.get(sql_unknown_setting(rc, i), "user_labels", null)] |
	some i, s in object.get(rc.change.after, "settings", [])
] if rc.type == "google_sql_database_instance"

# after_unknown.settings[i], or {} when it is absent or not a list.
sql_unknown_setting(rc, i) := u if {
	u := rc.change.after_unknown.settings[i]
	is_object(u)
} else := {}

tag_maps(rc) := [[object.get(rc.change.after, attr, null), object.get(rc.change.after_unknown, attr, null)] |
	some attr in ["tags", "tags_all"]
]

present_keys(maps) := {k |
	some pair in maps
	some m in pair
	is_object(m)
	some k, _ in m
}

any_unknown(maps) if {
	some pair in maps
	pair[1] == true
}

# The whole settings block of a Cloud SQL instance is unknown.
gcp_unknown(rc) if {
	rc.type == "google_sql_database_instance"
	rc.change.after_unknown.settings == true
}

gcp_unknown(rc) if any_unknown(label_maps(rc))

deny contains msg if {
	some t in gcp_labelled_types
	some rc in lib.written_of_type(t)
	not gcp_unknown(rc)
	missing := gcp_required - present_keys(label_maps(rc))
	count(missing) > 0
	msg := sprintf("%s: missing required labels %v (provider default_labels; Cloud SQL: settings.user_labels)", [rc.address, sort(missing)])
}

deny contains msg if {
	some t in aws_tagged_types
	some rc in lib.written_of_type(t)
	not any_unknown(tag_maps(rc))
	missing := aws_required - present_keys(tag_maps(rc))
	count(missing) > 0
	msg := sprintf("%s: missing required tags %v (set them through the provider default_tags)", [rc.address, sort(missing)])
}
