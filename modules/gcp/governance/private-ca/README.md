# Private CA (Certificate Authority Service) Module

Creates a Cloud Certificate Authority Service (CAS) CA pool and a single
certificate authority (ROOT or SUBORDINATE) for issuing private/internal
certificates. This is the GCP parity counterpart to the AWS ACM Private CA
module (`modules/aws/data/private-ca`).

## Features

- CA pool with configurable tier (`ENTERPRISE` / `DEVOPS`)
- ROOT (self-signed) or SUBORDINATE certificate authority
- Configurable subject, key algorithm, and lifetime
- Secure defaults: ENTERPRISE tier, RSA 4096 key, 10-year lifetime, deletion protection on
- CAS-specific safe lifecycle toggles (`ignore_active_certificates_on_deletion`, `skip_grace_period`)
- `enable_ca` gate: provision the pool without (yet) creating a billing CA

## Usage

```hcl
module "private_ca" {
  source = "../../governance/private-ca"

  project_id   = "my-project"
  location     = "europe-west1"
  ca_pool_name = "org-internal-pool"
  name         = "org-root-ca"

  ca_type = "ROOT"
  tier    = "ENTERPRISE"

  subject = {
    organization = "My Org"
    common_name  = "My Org Internal Root CA"
  }

  key_algorithm = "RSA_PKCS1_4096_SHA256"
  lifetime      = "315360000s" # 10 years

  labels = {
    team = "platform"
  }
}
```

<!-- BEGIN_TF_DOCS -->
Private CA Module - Certificate Authority Service (CAS)

GCP parity counterpart to the AWS ACM Private CA module
(modules/aws/data/private-ca). Provisions a CA pool and a single
Certificate Authority (ROOT or SUBORDINATE) for issuing private
(internal) certificates.

Like ACM PCA, Certificate Authority Service bills a fixed monthly
charge per CA in the ENTERPRISE tier from the moment the CA exists,
so CA creation is gated behind enable\_ca (default true — the pool is
always created, the CA can be staged out).

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	ca_pool_name = 
	name = 
	project_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_privateca_ca_pool.this (modules/gcp/governance/private-ca/main.tf#L26)
- resource.google_privateca_certificate_authority.this (modules/gcp/governance/private-ca/main.tf#L42)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_ca_pool_name"></a> [ca\_pool\_name](#input\_ca\_pool\_name) | Name of the CA pool (1-63 alphanumeric characters, hyphens, and underscores). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Certificate authority ID (1-63 alphanumeric characters, hyphens, and underscores). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID where the CA pool and certificate authority will be created (6-30 characters, lowercase alphanumeric and hyphens). | `string` | n/a | yes |
| <a name="input_ca_type"></a> [ca\_type](#input\_ca\_type) | Type of certificate authority. ROOT anchors the hierarchy (self-signed); SUBORDINATE is signed by a parent CA. | `string` | `"ROOT"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | When true (default) Terraform refuses to destroy the certificate authority, guarding against accidental teardown of the org's trust anchor. | `bool` | `true` | no |
| <a name="input_enable_ca"></a> [enable\_ca](#input\_enable\_ca) | When true (default) the certificate authority is created and enabled inside the pool. When false only the pool is created, staging the CA for a later apply. CAS bills per active CA, so this gate lets the pool exist without incurring CA charges. | `bool` | `true` | no |
| <a name="input_ignore_active_certificates_on_deletion"></a> [ignore\_active\_certificates\_on\_deletion](#input\_ignore\_active\_certificates\_on\_deletion) | When true, the CA can be deleted even while it has active issued certificates. Defaults to false — the safe setting that blocks deletion until certificates are dealt with. | `bool` | `false` | no |
| <a name="input_key_algorithm"></a> [key\_algorithm](#input\_key\_algorithm) | Algorithm used to generate the CA's key pair (e.g. RSA\_PKCS1\_4096\_SHA256, EC\_P256\_SHA256, EC\_P384\_SHA384). | `string` | `"RSA_PKCS1_4096_SHA256"` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to the CA pool and certificate authority. | `map(string)` | `{}` | no |
| <a name="input_lifetime"></a> [lifetime](#input\_lifetime) | Lifetime of the CA certificate as a duration in seconds (e.g. '315360000s' for 10 years). Defaults to 10 years, appropriate for a long-lived root. | `string` | `"315360000s"` | no |
| <a name="input_location"></a> [location](#input\_location) | GCP region for the CA pool and certificate authority (e.g. europe-west1). | `string` | `"europe-west1"` | no |
| <a name="input_skip_grace_period"></a> [skip\_grace\_period](#input\_skip\_grace\_period) | When true, deletion skips the CAS grace period and the CA is scheduled for permanent destruction immediately. Defaults to false so the recovery grace period is honoured. | `bool` | `false` | no |
| <a name="input_subject"></a> [subject](#input\_subject) | Subject placed in the CA certificate: organization (O) and common name (CN). | <pre>object({<br/>    organization = string<br/>    common_name  = string<br/>  })</pre> | <pre>{<br/>  "common_name": "org-internal-ca",<br/>  "organization": "Example Org"<br/>}</pre> | no |
| <a name="input_tier"></a> [tier](#input\_tier) | CA pool tier. ENTERPRISE supports per-certificate revocation and long-lived CAs; DEVOPS is cheaper but drops per-certificate features. Defaults to ENTERPRISE. | `string` | `"ENTERPRISE"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ca_pool_id"></a> [ca\_pool\_id](#output\_ca\_pool\_id) | Fully qualified ID of the CA pool (projects/<project>/locations/<location>/caPools/<name>). |
| <a name="output_ca_pool_name"></a> [ca\_pool\_name](#output\_ca\_pool\_name) | Name of the CA pool. |
| <a name="output_ca_state"></a> [ca\_state](#output\_ca\_state) | Current state of the certificate authority (e.g. ENABLED, STAGED), or null when enable\_ca is false. |
| <a name="output_certificate_authority_id"></a> [certificate\_authority\_id](#output\_certificate\_authority\_id) | Fully qualified ID of the certificate authority, or null when enable\_ca is false. |
<!-- END_TF_DOCS -->
