# Third parties, subprocessors and exit plans

DORA Art. 28(3) requires a register of information on ICT third-party service
providers. GDPR Art. 28 requires processor terms and a list of subprocessors.
HIPAA 45 CFR 164.308(b) requires a business associate agreement (BAA) before a
provider handles protected health information (PHI). PCI DSS 12.8 requires a
list of third-party service providers and their responsibilities.

This page is the landing zone's starting register. It lists the providers that
the code in this repository uses. Copy it into your GRC tool and keep it
current. It is not legal advice, and it does not replace your contracts.

**How to read it.** A vendor fact in this page has a link to the vendor's own
page. The links were last checked on 2026-11-12. Vendors change plans, terms
and regions often, so check each link again before you rely on it. Where this
page says **confirm with the vendor**, the vendor's public pages did not state
the fact, and you must get it in writing.

## Register

| Provider | Service used here | Data it can hold | Region control in this repository | Assurance to collect | DPA / BAA | Exit plan |
|:--|:--|:--|:--|:--|:--|:--|
| Google Cloud | Every GCP root (`envs/gcp/*`) | Everything you deploy on GCP, including audit logs and backups | `gcp.resourceLocations` organization policy (GRD-01) from `gcp.allowed_regions` | ISO/IEC certificates and SOC reports from [Compliance Reports Manager][gcp-crm]. PCI DSS scope: confirm with the vendor. | [Cloud Data Processing Addendum][gcp-dpa] (subprocessors: [list][gcp-sub]). [HIPAA BAA][gcp-hipaa]: you review and accept it ([terms][gcp-baa]). | The Terraform code is portable. Export data per service. Plan how you decrypt CMEK-encrypted data before you leave; key export options: confirm with the vendor. |
| Amazon Web Services | Every AWS root (`envs/aws/*`) | Everything you deploy on AWS, including the log archive and backup copies | Region SCP (GRD-06) from `aws.allowed_regions` | Auditor-issued reports and certifications from [AWS Artifact][aws-artifact] | [AWS DPA][aws-gdpr], part of the AWS Service Terms (subprocessors: [list][aws-sub]). [HIPAA BAA][aws-hipaa]: you accept it in AWS Artifact. Process PHI only in HIPAA-eligible services. | The Terraform code is portable. AWS Backup recovery points restore only into AWS; export the data itself before you leave. |
| HashiCorp (HCP Terraform) | State, runs, workspace variables, policy sets (`envs/tfc-admin`) | Terraform state (it can hold secrets; see CHG-03), workspace variables, run logs | Not in code. An [HCP Europe][hcp-eu] organization (`app.eu.terraform.io`) keeps resources in Europe. An existing organization cannot move there; you must create a new one. | [HashiCorp trust center][hcp-compliance]: a SOC 2 report (under NDA) and a PCI DSS AoC that names HCP Terraform. | [HashiCorp DPA][hcp-dpa] for HCP. Subprocessor list: confirm with the vendor. HIPAA BAA: confirm with the vendor. | [`state-backup.yml`](../runbooks/state-backup.md) copies each workspace's current state version to your own write-once buckets, and [`tfc-audit-trail.yml`](../runbooks/state-backup.md#audit-trail-export) copies the audit trail there (CHG-07). Workspace settings are code in `envs/tfc-admin`. |
| GitHub | Source code, pull requests, CI (GitHub Actions), OIDC tokens to the clouds | Source code, CI logs, workflow artifacts | Not in code | SOC 3, CSA CAIQ and ISO/IEC 27001:2022 from the [organization settings][gh-reports]. SOC 2 report: confirm with the vendor. | DPA: confirm with the vendor (it depends on your GitHub agreement). Subprocessors: [list][gh-sub]. HIPAA BAA: confirm with the vendor. | Git is portable. Workflows are YAML files in `.github/workflows`; rewrite them for the new CI. |
| Supabase | `envs/saas` (`enable_supabase`) | Application database, authentication users, storage, Vault secrets | `saas.allowed_regions` residency check (DP-09). Supabase regions are [AWS regions][supa-regions]. | [SOC 2 Type 2 report and ISO 27001 certificate][supa-security] in the dashboard (Team and Enterprise plans) | [Supabase DPA][supa-dpa]. Subprocessors: [list][supa-sub]. [HIPAA BAA][supa-security]: Team and Enterprise customers request it in the dashboard, and you must [configure HIPAA projects][supa-hipaa]. | `pg_dump` of the database plus an export of storage objects. This repository does not automate it; schedule it yourself. |
| Vercel | `envs/saas` (`enable_vercel`) | Front-end code and builds, function logs, environment variables | `saas.allowed_regions` residency check for the **function region only** (DP-09). The CDN is global; see below. | [SOC 2 Type 2, ISO 27001:2022 and PCI DSS AoC][vercel-compliance] from the Vercel Trust Center | [Vercel DPA][vercel-dpa]. Subprocessors: [list][vercel-sub] (Trust Center). [HIPAA BAA][vercel-compliance]: a paid add-on on Pro, by request on Enterprise. | The framework code is portable. Move DNS, domains and environment variables to the new host. |

### What the residency check covers

`envs/saas` fails its plan when the stack would process data outside
`saas.allowed_regions` (else `aws.allowed_regions`; with neither key there is
no check). Both vendors run on AWS, so the list holds AWS region names.

- **Supabase.** The project region slug is an AWS region name
  ([Supabase regions][supa-regions]), so it is compared as it is.
- **Vercel functions.** Each function region code maps to one AWS region in
  the "Region list" table of [Vercel regions][vercel-regions], for example
  `lhr1` to `eu-west-2` and `iad1` to `us-east-1`. The map lives in
  `envs/saas/main.tf`. A code that is not in the map fails the plan when an
  allow list is set (fail closed). The Vercel modules accept only the codes in
  that table.
- **Vercel CDN and edge cache: global.** Vercel's CDN has points of presence
  around the world, and requests reach a region through them
  ([Vercel regions][vercel-regions]). Vercel states that it may transfer data
  to the United States and other countries where it or its service providers
  process data ([Vercel compliance][vercel-compliance]). The residency check
  does not and cannot cover this. Do not put regulated data in cached
  responses, and read the Vercel DPA for transfers.
- **Not covered.** Vercel build infrastructure, logs and the Vercel control
  plane, Supabase control plane and support access, HCP Terraform and GitHub.
  Their location is a contract question; record it here.

## What you must still do

- Confirm each provider's current subprocessor list and how it notifies you of
  changes. Subscribe to the notifications where the vendor offers them
  (Supabase and GitHub do).
- Sign the BAA before PHI reaches a provider. Supabase and Vercel offer a BAA
  only on some plans. HashiCorp and GitHub: confirm with the vendor.
- For DORA: classify which providers support critical or important functions,
  record the contractual provisions (Art. 30) and test the exit plan.
- Record where each provider stores data that this repository cannot pin (the
  HCP Terraform organization's region, GitHub, Vercel logs and builds).
- Review the reports every year (SOC 2 CC9.2, ISO/IEC 27001 A.5.19 to A.5.22).

[gcp-crm]: https://cloud.google.com/security/compliance/compliance-reports-manager
[gcp-dpa]: https://cloud.google.com/terms/data-processing-addendum
[gcp-sub]: https://cloud.google.com/terms/subprocessors
[gcp-hipaa]: https://docs.cloud.google.com/docs/security/compliance/hipaa
[gcp-baa]: https://cloud.google.com/terms/hipaa-baa
[aws-artifact]: https://aws.amazon.com/artifact/
[aws-gdpr]: https://aws.amazon.com/compliance/gdpr-center/
[aws-sub]: https://aws.amazon.com/compliance/sub-processors/
[aws-hipaa]: https://aws.amazon.com/compliance/hipaa-compliance/
[hcp-eu]: https://developer.hashicorp.com/terraform/cloud-docs/europe
[hcp-compliance]: https://www.hashicorp.com/en/trust/compliance
[hcp-dpa]: https://www.hashicorp.com/en/trust/privacy/hcp-data-privacy
[gh-reports]: https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/accessing-compliance-reports-for-your-organization
[gh-sub]: https://docs.github.com/en/site-policy/privacy-policies/github-subprocessors
[supa-regions]: https://supabase.com/docs/guides/platform/regions
[supa-security]: https://supabase.com/security
[supa-dpa]: https://supabase.com/legal/dpa
[supa-sub]: https://supabase.com/legal/subprocessors
[supa-hipaa]: https://supabase.com/docs/guides/security/hipaa-compliance
[vercel-regions]: https://vercel.com/docs/regions
[vercel-compliance]: https://vercel.com/docs/security/compliance
[vercel-dpa]: https://vercel.com/legal/dpa
[vercel-sub]: https://vercel.com/legal/sub-processors
