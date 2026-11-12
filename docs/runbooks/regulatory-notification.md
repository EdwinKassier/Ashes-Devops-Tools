# Runbook: Regulatory incident and breach notification

**When to use:** a security incident may involve personal data, health data,
payment-card data, or a major disruption of a regulated service. Use it next to
the technical runbooks
([GCP incident response](incident-response.md),
[AWS incident response](aws-incident-response.md)).

> **This is not legal advice.** The deadlines below are a working summary.
> Each organization must confirm which rules apply to it, and how they apply,
> with its own legal counsel and the current forms of each regulator. National
> law can add shorter or stricter duties.

The clock usually starts when your organization becomes aware of the incident
(GDPR, NIS2, HIPAA), or when it classifies the incident as major (DORA initial
notification). It does not start when the investigation ends.

## 1. Roles (fill in before you need them)

| Role | Name | Backup | Decides |
|:--|:--|:--|:--|
| Incident commander | | | Severity, containment |
| Data protection officer | | | GDPR Art. 33 and 34 notification |
| Compliance officer (DORA, NIS2) | | | Major or significant classification, reports |
| HIPAA privacy officer | | | Breach risk assessment, notices |
| PCI contact | | | Acquirer and payment-brand notice |
| Legal counsel | | | Final wording, law enforcement contact |

Put the people who must see the first signal in `notifications.emails` in
`config/landing-zone.yaml`. It feeds the AWS security notification and CIS alarm
topics and the GCP control-plane alert channels (see
`config/landing-zone.example.yaml`). The landing zone has no separate list for
breach contacts. Keep the roles table above current in your own records.

## 2. Deadlines at a glance

Rows marked "verified" were checked against the legal text on the date in
section 7. Read that section for what was and was not checked.

| Regime | Trigger | First notice | Then | Final | To whom |
|:--|:--|:--|:--|:--|:--|
| GDPR and UK GDPR, Art. 33 | Personal-data breach, you are aware, unless unlikely to result in a risk to individuals | Without undue delay and, where feasible, within **72 hours** of awareness. A later notice must give the reasons for the delay | Information may follow in phases without undue delay (Art. 33(4)) | n/a | Supervisory authority |
| GDPR Art. 33(2) | You are a processor and become aware | Without undue delay | | | The controller |
| GDPR Art. 34 | Breach likely to result in a high risk to individuals | Without undue delay | Exceptions: data was effectively protected (for example encrypted), the high risk is no longer likely, or individual notice is disproportionate and a public notice replaces it | | Data subjects |
| DORA Art. 19(4) with Delegated Regulation (EU) 2025/301 Art. 5 (verified) | Major ICT-related incident | **Initial notification** as early as possible, within **4 hours** of classifying the incident as major and no later than **24 hours** after you became aware | **Intermediate report** at the latest **72 hours** after the initial notification, and an updated one without undue delay and when regular activities have recovered | **Final report** no later than **1 month** after the latest intermediate report | Competent authority |
| NIS2 Art. 23(4) | Significant incident | **Early warning** within **24 hours** of awareness | **Incident notification** within **72 hours** of awareness. An intermediate report on request of the CSIRT or authority | **Final report** no later than **1 month** after the incident notification. If the incident is still ongoing, a progress report then, and the final report within 1 month of the end of handling | CSIRT or competent authority |
| HIPAA 45 CFR 164.404 (verified) | Breach of unsecured PHI, discovered | Individuals without unreasonable delay and no later than **60 calendar days** after discovery | Media (164.406) if more than 500 residents of a State or jurisdiction are affected. HHS at the same time as individuals if 500 or more people are affected (164.408(b)) | HHS log for breaches of fewer than 500 people, reported within 60 days after the end of the calendar year of discovery (164.408(c)) | Individuals, HHS, media |
| HIPAA 45 CFR 164.410 (verified) | You are a business associate and discover a breach | Without unreasonable delay and no later than **60 calendar days** after discovery | | | The covered entity |
| PCI DSS v4.0.1 requirement 12.10.1 | Suspected or confirmed security incident affecting account data | Your incident response plan must cover it. The notice times and contacts come from your acquirer and payment-brand agreements. PCI DSS sets no fixed hour or day count | Forensic investigator if your acquirer or brand requires one | | Acquirer, payment brands |
| US SEC Form 8-K Item 1.05 (verified; listed US issuers only) | Cybersecurity incident you determine is material | **4 business days** after the materiality determination (a national-security delay can apply) | Amend the filing for information not known at first | | SEC |

Notes that change the counting:

- **DORA weekends.** If a DORA deadline falls on a weekend or bank holiday in the
  entity's Member State, the entity may submit by noon on the next working day.
  This does not apply to the initial notification or intermediate report of
  credit institutions, central counterparties, trading venues, or entities that
  are essential or important under NIS2, unless the competent authority decides
  otherwise (Art. 5(4) to (6) of the Delegated Regulation).
- **DORA late classification.** If you classify the incident as major more than
  24 hours after awareness, the initial notification is still due within 4 hours
  of classification (Art. 5(2)).
- **DORA missed deadline.** If you cannot meet a deadline, tell the competent
  authority without undue delay, no later than the deadline, and give the
  reasons (Art. 5(3)).
- **Overlap.** One incident can trigger several regimes at once, for example
  GDPR and NIS2, or DORA and GDPR. Run each clock in parallel.

## 3. Procedure

1. **T0: record awareness.** Open the incident ticket. Write the UTC time the
   organization became aware and who decided that. The deadlines above count
   from this field (DORA: from classification, with the 24-hour limit from
   awareness).
2. **Classify (target within 1 hour).** Answer and record: Is personal data
   involved (GDPR)? Is it PHI (HIPAA)? Is it cardholder data (PCI)? Are you a
   DORA financial entity, and does the incident meet the major-incident criteria
   of Delegated Regulation (EU) 2024/1772? Are you an NIS2 essential or
   important entity, and is the incident significant? Are you a listed US
   issuer, and could the incident be material?
3. **Preserve evidence before you change anything.** Run the commands in section
   4 and store the output in the incident folder.
4. **Start each clock that applies.** Put every deadline from section 2 in the
   ticket, with the owner from section 1.
5. **Draft the first notice.** Use the regulator's current form. State what you
   know, what you do not know yet, and when you will update.
6. **Approve and send.** Counsel and the decider from section 1 approve. Record
   the time sent and the reference number.
7. **Update on schedule.** Send intermediate and final reports as section 2
   requires.
8. **Close.** Hold the post-incident review (Step 6 of the incident response
   runbooks), record lessons and control changes, and update your risk register.

## 4. Evidence the landing zone gives you

Control IDs refer to [`docs/compliance/control-matrix.md`](../compliance/control-matrix.md).

| Question | AWS | GCP |
|:--|:--|:--|
| What did the identity do? | `aws cloudtrail lookup-events`, or Athena on the log-archive bucket (LOG-07, LOG-08) | `gcloud logging read 'protoPayload.authenticationInfo.principalEmail="<id>"' --organization=<ORG_ID>`, and the audit bucket (LOG-01, LOG-02) |
| Was data read? | S3 data events (LOG-07), Macie findings (DET-04) | Data Access logs, `DATA_READ` (LOG-01) |
| Threat findings | GuardDuty and Security Hub (DET-01, DET-02) | SCC findings topic (DET-03) |
| Who changed the infrastructure? | HCP Terraform run history and audit trail | Same |
| Are backups intact? | `aws backup list-recovery-points-by-backup-vault --backup-vault-name org-backup-copy-vault` when the central copy is on (BCK-01) | `gcloud backup-dr backups list` when the vault is on (BCK-07) |
| Log integrity | `aws cloudtrail validate-logs` | Locked retention policy on the audit bucket, when enabled (LOG-03) |

Check the control matrix for the current row of each control before you rely on
it: several are opt-in.

## 5. Templates

Keep these ready, with your own wording agreed by counsel:

- **Supervisory authority (GDPR Art. 33(3)).** Nature of the breach, categories
  and approximate numbers of people and records, contact point, likely
  consequences, measures taken or proposed.
- **DORA initial notification.** Use the fields of the current implementing
  technical standard template from your competent authority.
- **NIS2 early warning.** Whether an unlawful or malicious act is suspected and
  whether there may be a cross-border impact.
- **HIPAA individual notice (164.404(c)).** What happened and when, the types of
  information involved, steps individuals should take, what you are doing, and
  contact details.

File the sent versions in the incident folder.

## 6. Test it

Run a tabletop exercise at least once a year, with one scenario for each regime
that applies to you. Record the date, the clocks you started, the time each
notice was ready, and the gaps. DORA Art. 24 and 25 (digital operational
resilience testing), ISO 27001 A.5.24 and SOC 2 CC7.4 expect this kind of
exercise.

## 7. Sources and what was verified

Checked on 2026-11-12.

| Source | Status |
|:--|:--|
| DORA Delegated Regulation (EU) 2025/301, Art. 5: [Official Journal copy](https://eur-lex.europa.eu/eli/reg_del/2025/301/oj) | Verified. Read the Official Journal text through a PDF copy. The 4-hour, 24-hour, 72-hour and 1-month limits and their triggers match section 2. The classification criteria are in Delegated Regulation (EU) 2024/1772. |
| DORA, Regulation (EU) 2022/2554, [Art. 19](https://eur-lex.europa.eu/eli/reg/2022/2554/oj) | Not fetched from EUR-Lex (the site refused automated access). A third-party copy confirms Art. 19(4) sets the three submissions and refers the time limits to the technical standard. |
| GDPR, Regulation (EU) 2016/679, [Art. 33 and 34](https://eur-lex.europa.eu/eli/reg/2016/679/oj) | Not fetched from EUR-Lex. Checked against an unofficial copy at gdpr-info.eu ([Art. 33](https://gdpr-info.eu/art-33-gdpr/), [Art. 34](https://gdpr-info.eu/art-34-gdpr/)). Confirm against the Official Journal text. |
| NIS2, Directive (EU) 2022/2555, [Art. 23](https://eur-lex.europa.eu/eli/dir/2022/2555/oj) | Not fetched from EUR-Lex. Checked against an unofficial copy ([nis-2-directive.com](https://www.nis-2-directive.com/NIS_2_Directive_Article_23.html)). Confirm against the Official Journal text and your Member State's transposition. |
| HIPAA, [45 CFR 164.404 to 164.410](https://www.ecfr.gov/current/title-45/subtitle-A/subchapter-C/part-164/subpart-D) | Verified on eCFR. |
| SEC [final rule 33-11216](https://www.sec.gov/files/rules/final/2023/33-11216.pdf) (Form 8-K Item 1.05) | Verified. |
| PCI DSS v4.0.1 requirement 12.10.1 | Not fetched. The PCI Security Standards Council document library requires a sign-in. Section 2 makes no numeric claim for PCI DSS. Read the standard and your acquirer agreement. |

UK GDPR is described by its relationship to the EU text only. Check the UK
Information Commissioner's Office guidance for the UK rules. Sector rules not
listed here (for example FedRAMP, state breach laws, other regional privacy
laws) are out of scope and were not checked.

## See also

- [GCP Incident Response](incident-response.md) and
  [AWS Incident Response](aws-incident-response.md): technical containment and
  forensics.
- [Control matrix](../compliance/control-matrix.md): which controls produce the
  evidence in section 4.
- [Regulated environments](../architecture/regulated-environments.md): the
  opt-in class for estates that hold regulated data.
