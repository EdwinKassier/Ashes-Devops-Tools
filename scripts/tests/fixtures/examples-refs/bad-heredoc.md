```hcl
module "a" {
  source = "../../modules/gcp/network/tiered-vpc"
  subnet_cidrs = {}
  policy = <<-EOT
    { unbalanced
  EOT
}

module "b" {
  source = "../../modules/gcp/network/tiered-vpc"
  heredoc_bad_input = 1
}
```
