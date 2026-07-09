# network-access-analyzer

Optional AWS Network Access Analyzer scope for the SRA landing zone. A scope
encodes a network-**segmentation intent** as source -> destination resource-type
paths that AWS can continuously validate — for example, "no path exists from an
internet gateway to an isolated instance". A path that matches in an analysis is
a segmentation violation.

This module manages the **scope only**. There is no
`aws_ec2_network_insights_access_scope_analysis` Terraform resource, so scope
analyses are run **out-of-band** — via
`aws ec2 start-network-insights-access-scope-analysis`, a scheduled job, or the
console — against the `access_scope_id` output here.

The module is **optional and OFF by default** (`enable_network_access_analyzer =
false`). It requires the AWS provider **>= 6.43** (which first shipped the
`aws_ec2_network_insights_access_scope` resource); this module's provider floor
of `>= 6.46.0` covers that.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	
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


- resource.aws_ec2_network_insights_access_scope.this (modules/aws/network-access-analyzer/main.tf#L16)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_network_access_analyzer"></a> [enable\_network\_access\_analyzer](#input\_enable\_network\_access\_analyzer) | Whether to create the Network Access Analyzer scope. Off by default; the scope is optional. | `bool` | `false` | no |
| <a name="input_exclude_paths"></a> [exclude\_paths](#input\_exclude\_paths) | Paths excluded from the scope, expressed as source/destination AWS resource types. Excluded paths are ignored even if they would otherwise match. | <pre>list(object({<br/>    source_resource_types      = list(string)<br/>    destination_resource_types = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_match_paths"></a> [match\_paths](#input\_match\_paths) | Paths the scope matches, expressed as source/destination AWS resource types. A matched path in an out-of-band analysis is a segmentation-intent violation. Defaults to a single internet-gateway -> instance path. | <pre>list(object({<br/>    source_resource_types      = list(string)<br/>    destination_resource_types = list(string)<br/>  }))</pre> | <pre>[<br/>  {<br/>    "destination_resource_types": [<br/>      "AWS::EC2::Instance"<br/>    ],<br/>    "source_resource_types": [<br/>      "AWS::EC2::InternetGateway"<br/>    ]<br/>  }<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_scope_id"></a> [access\_scope\_id](#output\_access\_scope\_id) | ID of the Network Access Analyzer scope, or null when the analyzer is disabled. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "network_access_analyzer" {
  source = "../../modules/aws/network-access-analyzer"

  enable_network_access_analyzer = true

  # Segmentation intent: no internet-gateway -> instance path should exist.
  match_paths = [{
    source_resource_types      = ["AWS::EC2::InternetGateway"]
    destination_resource_types = ["AWS::EC2::Instance"]
  }]
}
```

Run an analysis out-of-band against the scope:

```sh
aws ec2 start-network-insights-access-scope-analysis \
  --network-insights-access-scope-id "$(terraform output -raw access_scope_id)"
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
