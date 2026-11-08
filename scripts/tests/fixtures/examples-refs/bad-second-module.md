```hcl
module "a" {
  source = "../../modules/gcp/network/tiered-vpc"
}

module "b" {
  source = "../../modules/gcp/network/nope-two"
}
```
