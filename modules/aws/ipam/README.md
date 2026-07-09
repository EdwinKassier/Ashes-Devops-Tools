# ipam

Hierarchical AWS VPC IPAM for the SRA landing zone. Creates a two-tier pool
topology in the private default scope: a single top-level pool that owns the
whole supernet (`top_cidr`), and one regional pool per enabled region sourced
from the top pool, each provisioning a per-region CIDR from `regional_cidrs`.
The regional pools are shared organization-wide via AWS RAM so member accounts
can allocate VPC CIDRs from centrally governed address space. In practice this
module is deployed in — and IPAM administration is delegated to — the network
account.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	org_arn = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_ram_principal_association.org (modules/aws/ipam/main.tf#L73)
- resource.aws_ram_resource_association.pools (modules/aws/ipam/main.tf#L66)
- resource.aws_ram_resource_share.this (modules/aws/ipam/main.tf#L61)
- resource.aws_vpc_ipam.this (modules/aws/ipam/main.tf#L14)
- resource.aws_vpc_ipam_pool.regional (modules/aws/ipam/main.tf#L41)
- resource.aws_vpc_ipam_pool.top (modules/aws/ipam/main.tf#L27)
- resource.aws_vpc_ipam_pool_cidr.regional (modules/aws/ipam/main.tf#L52)
- resource.aws_vpc_ipam_pool_cidr.top (modules/aws/ipam/main.tf#L34)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_org_arn"></a> [org\_arn](#input\_org\_arn) | ARN of the AWS organization (arn:aws:organizations::<mgmt-account>:organization/o-xxxx) used as the RAM principal so the shared pools are available org-wide. | `string` | n/a | yes |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions IPAM operates in. Each becomes an operating region on the IPAM and gets its own regional pool sourced from the top pool. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_description"></a> [description](#input\_description) | Description applied to the IPAM. | `string` | `"SRA landing zone hierarchical IPAM."` | no |
| <a name="input_regional_cidrs"></a> [regional\_cidrs](#input\_regional\_cidrs) | Map of region to the CIDR each regional pool provisions. Every key should be a region present in aws\_enabled\_regions and every CIDR should fall within top\_cidr. | `map(string)` | <pre>{<br/>  "eu-west-2": "10.0.0.0/12"<br/>}</pre> | no |
| <a name="input_share_name"></a> [share\_name](#input\_share\_name) | Name of the AWS RAM resource share used to share the regional IPAM pools organization-wide. | `string` | `"ipam-pools"` | no |
| <a name="input_top_cidr"></a> [top\_cidr](#input\_top\_cidr) | CIDR of the top-level supernet owned by the top IPAM pool. Regional pool CIDRs are carved from within this range. | `string` | `"10.0.0.0/8"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ipam_id"></a> [ipam\_id](#output\_ipam\_id) | The ID of the IPAM. |
| <a name="output_regional_pool_ids"></a> [regional\_pool\_ids](#output\_regional\_pool\_ids) | Map of region to the ID of its regional IPAM pool. |
| <a name="output_resource_share_arn"></a> [resource\_share\_arn](#output\_resource\_share\_arn) | ARN of the RAM resource share used to share the regional pools org-wide. |
| <a name="output_top_pool_id"></a> [top\_pool\_id](#output\_top\_pool\_id) | The ID of the top-level IPAM pool that owns the supernet. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "ipam" {
  source = "../../modules/aws/ipam"

  org_arn = "arn:aws:organizations::123456789012:organization/o-exampleorgid"

  # Defaults provision a single eu-west-2 region against a 10.0.0.0/8 supernet.
  # Override to add regions and their CIDR slices.
  aws_enabled_regions = ["eu-west-2", "eu-west-1"]
  regional_cidrs = {
    eu-west-2 = "10.0.0.0/12"
    eu-west-1 = "10.16.0.0/12"
  }
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
