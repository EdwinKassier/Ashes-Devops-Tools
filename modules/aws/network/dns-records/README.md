# dns-records (Route 53)

Write DNS records into an **existing** Route 53 hosted zone (audit H9, option C —
DNS unification). The AWS counterpart of
[`../../../gcp/network/dns-records`](../../../gcp/network/dns-records). This module
does not create the hosted zone; it adds records to a zone managed elsewhere. Use
it to keep SaaS custom-domain records (Vercel, Supabase) in the organization's
managed zone instead of a separate registrar.

Opt-in: with an empty `records` map it creates nothing. Simple (non-alias)
records only.

## Usage

```hcl
module "saas_dns" {
  source  = "../../modules/aws/network/dns-records"
  zone_id = "Z0123456789ABCDEFGHIJ"   # an existing hosted zone

  records = {
    vercel_app = { name = "app.example.com", type = "CNAME", records = ["cname.vercel-dns.com"] }
    supabase   = { name = "db.example.com",  type = "CNAME", records = ["abcdref.supabase.co"] }
    vercel_txt = { name = "_vercel.example.com", type = "TXT", ttl = 60, records = ["vc-domain-verify=..."] }
  }
}
```

For an apex domain, Vercel uses an A record to `76.76.21.21`. Supabase and Vercel
also publish verification TXT records during custom-domain setup; add them here.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	zone_id = 
	
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


- resource.aws_route53_record.this (modules/aws/network/dns-records/main.tf#L11)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | ID of the EXISTING Route 53 hosted zone to write records into (e.g. Z0123456789ABCDEFGHIJ). The zone must already exist. | `string` | n/a | yes |
| <a name="input_records"></a> [records](#input\_records) | DNS records to create in the hosted zone, keyed by a label. Default empty<br/>(creates nothing). Each entry sets the record name, type, ttl, and records<br/>(the rrdata values). Common SaaS records:<br/>  Vercel subdomain:  { name = "app.example.com", type = "CNAME", records = ["cname.vercel-dns.com"] }<br/>  Vercel apex:       { name = "example.com",     type = "A",     records = ["76.76.21.21"] }<br/>  Supabase domain:   { name = "db.example.com",  type = "CNAME", records = ["<project-ref>.supabase.co"] }<br/>  Verification TXT:  { name = "\_vercel.example.com", type = "TXT", records = ["vc-domain-verify=..."] } | <pre>map(object({<br/>    name    = string<br/>    type    = string<br/>    ttl     = optional(number, 300)<br/>    records = list(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_record_fqdns"></a> [record\_fqdns](#output\_record\_fqdns) | Map of record key to the created record's fully qualified domain name. |
| <a name="output_record_names"></a> [record\_names](#output\_record\_names) | Map of record key to the created record name. |
<!-- END_TF_DOCS -->
