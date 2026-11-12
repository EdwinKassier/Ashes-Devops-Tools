# Compliance

Framework mappings for the landing zone.

| Document | What it is |
|:---------|:-----------|
| [Control Matrix](control-matrix.md) | Implemented controls mapped to SOC 2 TSC, ISO/IEC 27001:2022 Annex A, NIST SP 800-53 Rev 5 and CIS GCP/AWS Foundations. Each control lists its code path, enabling flag and default. Also covers gaps, customer responsibilities and how to collect audit evidence. |
| [Framework crosswalk](framework-crosswalk.md) | PCI DSS v4.0.1, HIPAA Security Rule, DORA, NIST SP 800-53 Rev 5, FedRAMP Moderate (reference only) and ISO/IEC 27001:2022 requirements mapped to the matrix rows, with the default state of each control, the customer share, what is out of scope, and which requirement IDs were checked against which source. |
| [Third parties](third-parties.md) | The starting register of third-party providers (Google Cloud, AWS, HCP Terraform, GitHub, Supabase, Vercel): data held, region control, assurance reports, DPA and BAA, and exit plan. Also says what the SaaS residency check covers. |

The matrix is **design evidence**: it shows what the code does and how it is
switched on. Your auditor will also need **operating evidence** from your
deployed estate over the audit period. The matrix's evidence section lists where
to get it.

Keep the matrix in step with the code. When you add or change a control, or
flip a default, update its row, and update [Known Gaps](../known-gaps.md) if the
control is preview or open.
