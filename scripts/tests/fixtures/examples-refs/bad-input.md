```hcl
module "a" {
  source = "./modules/gcp/network/tiered-vpc"
  not_a_real_input = 1
}
```
