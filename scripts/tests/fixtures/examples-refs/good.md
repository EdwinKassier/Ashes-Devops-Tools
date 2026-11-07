# Good

See `envs/gcp/workload` for the root.

```hcl
module "vpc" {
  source = "../../modules/gcp/network/tiered-vpc"

  # a comment = ignored
  subnet_cidrs = {
    web = "10.0.0.0/24"
    bogus_nested = "x"
  }
  count = 1
}
```

```yaml
gcp:
  network:
    vpn: {}
```

```text
module "x" { source = "modules/nope/nope" }
```
