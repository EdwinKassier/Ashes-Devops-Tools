Root file: `envs/gcp/workload/main.tf`.

```hcl
module "r" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"
  anything = 1
}

module "g" {
  source = "git::https://example.com/x.git//m"
  whatever = 1
}
```
