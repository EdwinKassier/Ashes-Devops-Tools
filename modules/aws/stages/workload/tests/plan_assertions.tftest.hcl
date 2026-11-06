# Plan-assertion tests for the aws-workload stage.
#
# Two mock providers: the default aws provider and the aws.us_east_1 alias the
# stage declares (required by the optional edge-security module). The spoke TGW
# attachment consumes module.vpc.subnet_ids_by_tier["tgw"], which is unknown at
# plan under mock (a for_each / index over unknown ids would break). So we
# override_module the vpc child with a KNOWN vpc id + subnet-tier map and run
# under `command = apply` to assert the wiring concretely.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  tgw_id                   = "tgw-000000000000abcd"
  flow_log_destination_arn = "arn:aws:s3:::ashes-org-log-archive"
  log_archive_bucket_name  = "ashes-org-log-archive"
  config_role_arn          = "arn:aws:iam::222222222222:role/config-recorder"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

# Known spoke vpc id + tgw-tier subnets so the attachment wiring is plan-known.
override_module {
  target = module.vpc
  outputs = {
    vpc_id   = "vpc-workload00000001"
    vpc_cidr = "10.20.0.0/16"
    subnet_ids_by_tier = {
      private  = ["subnet-wl-prv-a", "subnet-wl-prv-b"]
      isolated = ["subnet-wl-iso-a", "subnet-wl-iso-b"]
      tgw      = ["subnet-wl-tgw-a", "subnet-wl-tgw-b"]
    }
    route_table_ids_by_tier = {
      private  = ["rtb-wl-prv-a", "rtb-wl-prv-b"]
      isolated = ["rtb-wl-iso-a", "rtb-wl-iso-b"]
      tgw      = ["rtb-wl-tgw-a", "rtb-wl-tgw-b"]
    }
  }
}

# Known account-baseline output so the "baseline present" assertion is
# non-vacuous without evaluating the child's real resources under apply.
override_module {
  target  = module.account_baseline
  outputs = { ebs_encryption_regions = ["eu-west-2"] }
}

# The systems-manager child's aws_ssm_default_patch_baseline validates that
# baseline_id is a real ARN; the mock generates a non-ARN placeholder that fails
# under apply. Override it (the assertions only care that the module is present,
# which override_module preserves — count-instantiated modules stay in the graph).
override_module {
  target = module.systems_manager[0]
}

run "composes_workload_edge_disabled" {
  command = apply

  # The spoke attaches to the SHARED transit gateway passed in (routing contract).
  assert {
    condition     = aws_ec2_transit_gateway_vpc_attachment.spoke[0].transit_gateway_id == var.tgw_id
    error_message = "spoke attachment must target the shared transit gateway var.tgw_id"
  }

  # The workload never touches the hub's segment routing: default route-table
  # association/propagation are both disabled (the network account manages them).
  assert {
    condition = (
      aws_ec2_transit_gateway_vpc_attachment.spoke[0].transit_gateway_default_route_table_association == false &&
      aws_ec2_transit_gateway_vpc_attachment.spoke[0].transit_gateway_default_route_table_propagation == false
    )
    error_message = "spoke attachment must not use the TGW default route tables"
  }

  # The attachment is placed in the spoke's tgw-tier subnets.
  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.spoke[0].subnet_ids) == 2
    error_message = "spoke attachment must span the tgw-tier subnets (one per AZ)"
  }

  # The account baseline is present: its region-scope output surfaces (proves the
  # child module was composed and evaluated).
  assert {
    condition     = contains(module.account_baseline.ebs_encryption_regions, "eu-west-2")
    error_message = "account_baseline must enforce EBS encryption in the enabled region"
  }

  # Spoke routing: the private tier default-routes (0.0.0.0/0) to the shared
  # TGW; the isolated tier gets no TGW route.
  assert {
    condition = (
      keys(output.tgw_routes) == ["private"] &&
      output.tgw_routes["private"][0].destination_cidr_block == "0.0.0.0/0" &&
      output.tgw_routes["private"][0].transit_gateway_id == var.tgw_id
    )
    error_message = "spoke private tier must route 0.0.0.0/0 to the shared transit gateway"
  }

  # Name is derived, not hard-coded (legacy "workload" when environment is unset).
  assert {
    condition     = output.name == "workload" && aws_ec2_transit_gateway_vpc_attachment.spoke[0].tags["Name"] == "workload-spoke"
    error_message = "with no environment/name the legacy workload name must be kept"
  }

  # spoke vpc id surfaces through the stage output (wiring proof).
  assert {
    condition     = output.vpc_id == "vpc-workload00000001"
    error_message = "vpc_id output must surface module.vpc.vpc_id"
  }

  # enable_edge defaults false => the edge-security module is absent.
  assert {
    condition     = length(module.edge_security) == 0
    error_message = "edge-security module must be absent when enable_edge is false"
  }

  # enable_ssm defaults true => the systems-manager module is present.
  assert {
    condition     = length(module.systems_manager) == 1
    error_message = "systems-manager module must be present when enable_ssm is true"
  }
}

run "composes_workload_edge_enabled" {
  command = apply

  variables {
    enable_edge             = true
    edge_origin_domain_name = "app.example.com"
  }

  # enable_edge true => the edge-security module is instantiated.
  assert {
    condition     = length(module.edge_security) == 1
    error_message = "edge-security module must be present when enable_edge is true"
  }
}

# config_role_arn = null: the recorder uses the account's Config service-linked
# role, created by config-org (no hand-made recorder role needed).
run "config_recorder_defaults_to_service_linked_role" {
  command = apply

  variables {
    config_role_arn = null
  }

  override_data {
    target = module.config_recorder.data.aws_caller_identity.current[0]
    values = { account_id = "222222222222" }
  }

  assert {
    condition     = output.config_role_arn == "arn:aws:iam::222222222222:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "With config_role_arn = null the recorder must resolve to the service-linked role."
  }
}

# Boundary propagation (tfc-oidc-baseline): workload_roles default to the
# workload account's tfc-apply-boundary, derived from the default provider.
run "workload_roles_carry_tfc_apply_boundary" {
  command = plan

  override_data {
    target = data.aws_caller_identity.current[0]
    values = { account_id = "222222222222" }
  }

  override_data {
    target = data.aws_partition.current[0]
    values = { partition = "aws" }
  }

  assert {
    condition     = local.permissions_boundary_arn == "arn:aws:iam::222222222222:policy/tfc-apply-boundary"
    error_message = "The workload boundary ARN (passed to iam_role) must be derived from the workload-account provider."
  }
}

run "workload_boundary_disabled_with_null_name" {
  command = plan

  variables {
    tfc_apply_boundary_policy_name = null
  }

  assert {
    condition     = local.permissions_boundary_arn == null && length(data.aws_caller_identity.current) == 0
    error_message = "tfc_apply_boundary_policy_name = null must disable the boundary."
  }
}
