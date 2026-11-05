# Host stage: network observability (VPC flow logs export, packet mirroring).
# Part of modules/gcp/stages/host.

# =============================================================================
# VPC FLOW LOGS EXPORT
# =============================================================================

data "google_project" "current" {
  count = var.enable_vpc_flow_logs_export ? 1 : 0

  project_id = var.project_id
}

module "flow_logs_kms" {
  source = "../../governance/kms"
  count  = var.enable_vpc_flow_logs_export ? 1 : 0

  project_id   = var.project_id
  keyring_name = "${var.project_prefix}-flow-logs"
  location     = var.region

  keys = {
    "vpc-flow-logs" = {
      encrypter_decrypters = [
        "serviceAccount:bq-${data.google_project.current[0].number}@bigquery-encryption.iam.gserviceaccount.com",
        "serviceAccount:service-${data.google_project.current[0].number}@gs-project-accounts.iam.gserviceaccount.com",
      ]
    }
  }
}

module "vpc_flow_logs" {
  source = "../../network/vpc-flow-logs"
  count  = var.enable_vpc_flow_logs_export ? 1 : 0

  project_id = var.project_id
  sink_name  = var.vpc_flow_logs_sink_name
  # When this stage creates the BigQuery dataset, derive the sink destination from it
  # (the vpc-flow-logs module always requires a non-empty destination). An explicit
  # vpc_flow_logs_destination still wins.
  destination = (
    var.vpc_flow_logs_destination != "" ? var.vpc_flow_logs_destination :
    var.vpc_flow_logs_create_bigquery_dataset ? "bigquery.googleapis.com/projects/${var.project_id}/datasets/${var.vpc_flow_logs_bigquery_dataset_id}" :
    ""
  )

  create_bigquery_dataset            = var.vpc_flow_logs_create_bigquery_dataset
  bigquery_dataset_id                = var.vpc_flow_logs_bigquery_dataset_id
  bigquery_location                  = var.vpc_flow_logs_bigquery_location
  bigquery_partition_expiration_days = var.vpc_flow_logs_retention_days
  bigquery_kms_key_name              = module.flow_logs_kms[0].key_names["vpc-flow-logs"]

  create_storage_bucket  = var.vpc_flow_logs_create_storage_bucket
  storage_bucket_name    = var.vpc_flow_logs_storage_bucket_name
  storage_location       = var.vpc_flow_logs_storage_location
  storage_retention_days = var.vpc_flow_logs_retention_days
  storage_kms_key_name   = module.flow_logs_kms[0].key_names["vpc-flow-logs"]

  labels = var.labels
}

# =============================================================================
# PACKET MIRRORING
# =============================================================================

module "packet_mirroring" {
  source   = "../../network/packet-mirroring"
  for_each = var.packet_mirroring_policies

  project_id = var.project_id
  name       = each.key
  region     = each.value.region
  network    = var.enable_networking ? module.vpc[0].self_link : var.existing_network_self_link

  collector_ilb_url    = each.value.collector_ilb_url
  mirrored_instances   = try(each.value.mirrored_instances, [])
  mirrored_subnetworks = try(each.value.mirrored_subnetworks, [])
  mirrored_tags        = try(each.value.mirrored_tags, [])
  filter_ip_protocols  = try(each.value.filter_ip_protocols, [])
  filter_cidr_ranges   = try(each.value.filter_cidr_ranges, [])
  filter_direction     = try(each.value.filter_direction, "BOTH")
  priority             = try(each.value.priority, 1000)
  enable               = try(each.value.enable, true)
}

