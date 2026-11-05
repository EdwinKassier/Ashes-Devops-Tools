# dns-records

Write DNS record sets into an **existing** Cloud DNS managed zone (audit H9,
option C — DNS unification). Unlike [`../dns`](../dns), this module does not own
the zone; it adds records to a zone created elsewhere. Use it to keep SaaS
custom-domain records (Vercel, Supabase) in the organization's managed zone
instead of a separate registrar.

Opt-in: with an empty `records` map it creates nothing.

## Usage

```hcl
module "saas_dns" {
  source       = "../../modules/gcp/network/dns-records"
  project_id   = local.dns_project_id
  managed_zone = "example-com"   # an existing Cloud DNS zone

  records = {
    vercel_app = { name = "app.example.com.", type = "CNAME", rrdatas = ["cname.vercel-dns.com."] }
    supabase   = { name = "db.example.com.",  type = "CNAME", rrdatas = ["abcdref.supabase.co."] }
    vercel_txt = { name = "_vercel.example.com.", type = "TXT", ttl = 60, rrdatas = ["\"vc-domain-verify=...\""] }
  }
}
```

Record names are fully qualified and end with a dot. For an apex domain, Vercel
uses an A record to `76.76.21.21` instead of a CNAME. Supabase and Vercel also
publish verification TXT records during custom-domain setup; add them here too.

The AWS Route 53 counterpart for an AWS-managed zone is a symmetric follow-up.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	managed_zone =
	project_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_dns_record_set.this (modules/gcp/network/dns-records/main.tf#L9)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_managed_zone"></a> [managed\_zone](#input\_managed\_zone) | Name of the EXISTING Cloud DNS managed zone to write records into (not the DNS name). The zone must already exist in var.project\_id. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | GCP project that holds the Cloud DNS managed zone. | `string` | n/a | yes |
| <a name="input_records"></a> [records](#input\_records) | DNS record sets to create in the zone, keyed by a label. Default empty (creates<br/>nothing). Each entry sets the record name (a fully qualified name ending in a<br/>dot), type, ttl, and rrdatas. Common SaaS records:<br/>  Vercel subdomain:  { name = "app.example.com.", type = "CNAME", rrdatas = ["cname.vercel-dns.com."] }<br/>  Vercel apex:       { name = "example.com.",     type = "A",     rrdatas = ["76.76.21.21"] }<br/>  Supabase domain:   { name = "db.example.com.",  type = "CNAME", rrdatas = ["<project-ref>.supabase.co."] }<br/>  Verification TXT:  { name = "\_vercel.example.com.", type = "TXT", rrdatas = ["\"vc-domain-verify=...\""] } | <pre>map(object({<br/>    name    = string<br/>    type    = string<br/>    ttl     = optional(number, 300)<br/>    rrdatas = list(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_record_fqdns"></a> [record\_fqdns](#output\_record\_fqdns) | Map of record key to the created record's fully qualified name. |
| <a name="output_record_ids"></a> [record\_ids](#output\_record\_ids) | Map of record key to the created record set ID. |
<!-- END_TF_DOCS -->
