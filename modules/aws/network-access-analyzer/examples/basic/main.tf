# Basic working example for the aws/network-access-analyzer module.
# Enables the scope and encodes the segmentation intent "no path from the
# internet gateway reaches an instance". Analyses against the scope are run
# out-of-band. Run `terraform init && terraform validate` here to check it.

module "network_access_analyzer" {
  source = "../../"

  enable_network_access_analyzer = true

  match_paths = [{
    source_resource_types      = ["AWS::EC2::InternetGateway"]
    destination_resource_types = ["AWS::EC2::Instance"]
  }]
}
