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
    condition     = aws_ec2_transit_gateway_vpc_attachment.spoke.transit_gateway_id == var.tgw_id
    error_message = "spoke attachment must target the shared transit gateway var.tgw_id"
  }

  # The workload never touches the hub's segment routing: default route-table
  # association/propagation are both disabled (the network account manages them).
  assert {
    condition = (
      aws_ec2_transit_gateway_vpc_attachment.spoke.transit_gateway_default_route_table_association == false &&
      aws_ec2_transit_gateway_vpc_attachment.spoke.transit_gateway_default_route_table_propagation == false
    )
    error_message = "spoke attachment must not use the TGW default route tables"
  }

  # The attachment is placed in the spoke's tgw-tier subnets.
  assert {
    condition     = length(aws_ec2_transit_gateway_vpc_attachment.spoke.subnet_ids) == 2
    error_message = "spoke attachment must span the tgw-tier subnets (one per AZ)"
  }

  # The account baseline is present: its region-scope output surfaces (proves the
  # child module was composed and evaluated).
  assert {
    condition     = contains(module.account_baseline.ebs_encryption_regions, "eu-west-2")
    error_message = "account_baseline must enforce EBS encryption in the enabled region"
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
