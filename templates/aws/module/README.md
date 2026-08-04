# MODULE_NAME

<!-- BEGIN_TF_DOCS -->
<!-- terraform-docs output goes here — run `make docs` to regenerate -->
<!-- END_TF_DOCS -->

## Usage

```hcl
module "example" {
  source = "../../modules/MODULE_NAME"

  name = "example-param"
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example,
and [`examples/aliased/`](examples/aliased/main.tf) for the cross-account
aliased-provider reference pattern.
