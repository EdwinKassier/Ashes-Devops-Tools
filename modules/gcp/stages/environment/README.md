# Environment Stage

One application environment, composed: the composition behind every
`gcp-workload-<env>` workspace. In the environment's Shared VPC host project it
creates:

- the spoke network ([`net-spoke`](../net-spoke/), label `host`): Shared VPC
  host, tiered subnets, NAT, PSA, PSC, hub peering or an NCC spoke, the hub DNS
  peering zone, flow-log export, Cloud Armor, and the environment VPC-SC
  perimeter with its default ingress and egress policies;
- an optional budget ([`governance/billing`](../../governance/billing/));
- the service team registry, one [`stages/workload`](../workload/) service
  project per team;
- VM snapshot schedules and VM Manager patching in the host project and every
  team project;
- the opt-in SaaS secret bridge ([`data/secret-manager`](../../data/secret-manager/));
- the application golden path ([`stages/app-services`](../app-services/)), with
  services optionally placed in a team project (`service_team`);
- public ingress: one [`network/app-ingress`](../../network/app-ingress/) load
  balancer per exposed service.

The caller resolves config and upstream contracts and passes plain values; this
module reads no remote state and no config file. It is called once from
[`envs/gcp/workload`](../../../../envs/gcp/workload/main.tf) (`module "environment"`),
whose `moved.tf` moves the state of the inline composition that root held before.

## Usage

```hcl
module "environment" {
  source = "../../../modules/gcp/stages/environment"

  environment          = "dev"
  project_prefix       = "acme"
  org_id               = "123456789012"
  billing_account      = "000000-111111-222222"
  admin_project_number = "111111111111"

  host_project = {
    project_id     = "acme-dev-host-abcd"
    project_number = "222222222222"
    folder_id      = "folders/111"
    region         = "europe-west1"
    cidr_block     = "10.10.0.0/16"
  }

  hub = {
    peerings = {
      "hub-peering" = {
        peer_network         = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
        export_custom_routes = true
        import_custom_routes = true
      }
    }
  }

  app_services = { api = {} }
}
```

The `components` output is a plan-time summary (which components exist, and
their keys) for wiring checks.

<!-- BEGIN_TF_DOCS -->
Copyright 2026 Ashes

Environment Stage - one application environment, composed.

The composition behind every gcp-workload-<env> workspace: the spoke network
(net-spoke, with the environment VPC-SC perimeter), the budget, the service
team registry (stages/workload), VM backup and OS patching, the SaaS secret
bridge, the application golden path (stages/app-services) and public ingress
(network/app-ingress). The caller resolves config and upstream contracts and
passes plain values; this module reads no remote state.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	admin_project_number =
	billing_account =
	environment =
	host_project =
	org_id =
	project_prefix =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.46.2 |

## Modules


- app_ingress - ../../network/app-ingress
- app_services - ../app-services
- budget - ../../governance/billing
- host - ../net-spoke
- os_patch_management - ../../ops/os-config
- saas_secret_bridge - ../../data/secret-manager
- service_team - ../workload
- vm_backup_policy - ../../backup/backup-plan


## Resources

The following resources are created:


- resource.google_project_service.osconfig (modules/gcp/stages/environment/main.tf#L258)
- data source.google_project.host_project (modules/gcp/stages/environment/main.tf#L70)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_project_number"></a> [admin\_project\_number](#input\_admin\_project\_number) | Project number of the Terraform admin project (the gcp-organization contract). The default perimeter ingress policy admits its Workload Identity pools. | `string` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account for the budget and the service-team projects, bare (XXXXXX-XXXXXX-XXXXXX) or billingAccounts/ form (the gcp-organization contract billing\_account). | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Application environment name (e.g. dev, staging, prod). Names the VPC, the perimeter, the flow-log dataset and the ingress load balancers. | `string` | n/a | yes |
| <a name="input_host_project"></a> [host\_project](#input\_host\_project) | The environment's Shared VPC host project, from the gcp-projects contract environment\_config[<environment>]: project\_id, project\_number, folder\_id (folders/NNN or bare), region and the VPC cidr\_block. | <pre>object({<br/>    project_id     = string<br/>    project_number = string<br/>    folder_id      = string<br/>    region         = string<br/>    cidr_block     = string<br/>  })</pre> | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Bare numeric organization ID (the gcp-organization contract org\_id). | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Landing-zone name prefix (org.prefix). Names the VPC (<prefix>-<environment>-vpc) and the budget. | `string` | n/a | yes |
| <a name="input_app_platform"></a> [app\_platform](#input\_app\_platform) | Settings shared by every app service: subnetwork\_id (null = the first private subnet), bootstrap\_image (first revision), artifact\_registry\_kms\_key\_name, enable\_vulnerability\_scanning, the app-deploy WIF pool (enable\_deploy\_wif, deploy\_wif\_pool\_id, github\_repository\_owner\_id), alerts (enable\_alerts, alert\_notification\_channel\_ids) and the optional GKE Autopilot cluster (gke). | <pre>object({<br/>    subnetwork_id                  = optional(string)<br/>    bootstrap_image                = optional(string, "us-docker.pkg.dev/cloudrun/container/hello")<br/>    artifact_registry_kms_key_name = optional(string)<br/>    enable_vulnerability_scanning  = optional(bool, true)<br/>    enable_deploy_wif              = optional(bool, false)<br/>    deploy_wif_pool_id             = optional(string)<br/>    github_repository_owner_id     = optional(string)<br/>    enable_alerts                  = optional(bool, true)<br/>    alert_notification_channel_ids = optional(list(string), [])<br/>    gke = optional(object({<br/>      enabled                = optional(bool, false)<br/>      master_ipv4_cidr_block = optional(string, "172.16.0.0/28")<br/>      master_authorized_networks = optional(list(object({<br/>        cidr_block   = string<br/>        display_name = optional(string)<br/>      })), [])<br/>      cluster_secondary_range_name  = optional(string)<br/>      services_secondary_range_name = optional(string)<br/>    }), {})<br/>  })</pre> | `{}` | no |
| <a name="input_app_services"></a> [app\_services](#input\_app\_services) | Application services keyed by service name, in the shape of the modules/gcp/stages/app-services `services` input (which validates them). `service_team = "<key>"` deploys a service into that service team's project. Services named in public\_ingress default to LB-only ingress with unauthenticated invocation. | `any` | `{}` | no |
| <a name="input_budget"></a> [budget](#input\_budget) | Environment budget: monthly\_limit in currency (0 = no budget, topic or notifier) and the ISO 4217 currency. | <pre>object({<br/>    monthly_limit = optional(number, 0)<br/>    currency      = optional(string, "USD")<br/>  })</pre> | `{}` | no |
| <a name="input_cloud_armor"></a> [cloud\_armor](#input\_cloud\_armor) | Environment Cloud Armor policy: enabled, owasp\_rules, adaptive\_protection, owasp\_sensitivity (1 strictest to 4). Public ingress attaches it to every backend, so the caller enables it whenever ingress is on. | <pre>object({<br/>    enabled             = optional(bool, false)<br/>    owasp_rules         = optional(bool, false)<br/>    adaptive_protection = optional(bool, false)<br/>    owasp_sensitivity   = optional(number, 2)<br/>  })</pre> | `{}` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Deletion protection for the network core, Cloud SQL and the GKE cluster. | `bool` | `true` | no |
| <a name="input_hub"></a> [hub](#input\_hub) | Hub connectivity resolved from the gcp-network-hub contract: connectivity (peering \| ncc), ncc (hub\_id, group), the hub VPC peerings and the DNS peering zones. Empty maps = standalone (no hub). | <pre>object({<br/>    connectivity = optional(string, "peering")<br/>    ncc = optional(object({<br/>      hub_id = optional(string)<br/>      group  = optional(string, "edge")<br/>    }), {})<br/>    peerings = optional(map(object({<br/>      peer_network           = string<br/>      create_reverse_peering = optional(bool, true)<br/>      export_custom_routes   = optional(bool, false)<br/>      import_custom_routes   = optional(bool, false)<br/>    })), {})<br/>    dns_zones = optional(map(object({<br/>      dns_name        = string<br/>      visibility      = string<br/>      description     = optional(string)<br/>      dnssec_enabled  = optional(bool, false)<br/>      peering_network = optional(string)<br/>    })), {})<br/>  })</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels applied to every resource the environment creates. | `map(string)` | `{}` | no |
| <a name="input_network"></a> [network](#input\_network) | Spoke VPC settings: flow\_logs (aggregation\_interval, sampling 0.0-1.0), flow\_logs\_retention\_days for the BigQuery export, and private\_service\_connect\_target (all-apis \| vpc-sc; null derives vpc-sc once the perimeter is enforced, else all-apis). | <pre>object({<br/>    flow_logs = optional(object({<br/>      aggregation_interval = optional(string, "INTERVAL_5_SEC")<br/>      sampling             = optional(number, 0.1)<br/>    }), {})<br/>    flow_logs_retention_days       = optional(number, 30)<br/>    private_service_connect_target = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_public_ingress"></a> [public\_ingress](#input\_public\_ingress) | app\_services entries to expose through a global external Application Load Balancer each, keyed by service name: domains, optional dns\_managed\_zone (Cloud DNS zone in the host project for the A records), enable\_cdn. Empty = no public ingress. | <pre>map(object({<br/>    domains          = list(string)<br/>    dns_managed_zone = optional(string)<br/>    enable_cdn       = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_saas_secret_bridge"></a> [saas\_secret\_bridge](#input\_saas\_secret\_bridge) | Opt-in Secret Manager secret in the host project holding saas\_secret\_bridge\_value: enabled, secret\_name, accessor\_members (prefixed IAM members) and value\_version (the write-only version counter; bump it to re-write the value). | <pre>object({<br/>    enabled          = optional(bool, false)<br/>    secret_name      = optional(string, "supabase-connection")<br/>    accessor_members = optional(list(string), [])<br/>    value_version    = optional(number, 1)<br/>  })</pre> | `{}` | no |
| <a name="input_saas_secret_bridge_value"></a> [saas\_secret\_bridge\_value](#input\_saas\_secret\_bridge\_value) | The bridged connection payload (JSON) written write-only into the saas\_secret\_bridge secret. Required when saas\_secret\_bridge.enabled. | `string` | `null` | no |
| <a name="input_service_teams"></a> [service\_teams](#input\_service\_teams) | Service team registry: one stages/workload service project per entry, in the environment folder and attached to the Shared VPC. Fields as in envs/gcp/workload var.service\_teams. | <pre>map(object({<br/>    project_admin_group_email    = string<br/>    activate_apis                = optional(list(string), [])<br/>    project_admin_roles          = optional(list(string), [])<br/>    enable_shared_vpc_attachment = optional(bool, true)<br/>    enable_gke_network_user      = optional(bool, false)<br/>    shared_vpc_subnets = optional(map(object({<br/>      region      = string<br/>      subnet_name = string<br/>    })), {})<br/>    labels = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_vm_operations"></a> [vm\_operations](#input\_vm\_operations) | VM backup and patching in the host project and every service-team project: enable\_backup\_policy with backup\_schedules (modules/gcp/backup/backup-plan `schedules`; null = one daily vm-daily-snapshots policy), enable\_os\_patch\_management with os\_patch\_deployments (modules/gcp/ops/os-config `patch_deployments`; null = one weekly-os-patch deployment). | <pre>object({<br/>    enable_backup_policy       = optional(bool, true)<br/>    backup_schedules           = optional(any)<br/>    enable_os_patch_management = optional(bool, true)<br/>    os_patch_deployments       = optional(any)<br/>  })</pre> | `{}` | no |
| <a name="input_vpc_service_controls"></a> [vpc\_service\_controls](#input\_vpc\_service\_controls) | The environment VPC-SC perimeter. access\_policy\_name null = no perimeter.<br/>perimeter\_title null = "<ENVIRONMENT> Perimeter". enable\_dry\_run keeps the<br/>perimeter in dry-run; dry\_run\_restricted\_services stages a dry-run delta on<br/>an enforced perimeter. Empty ingress\_policies / egress\_policies use the<br/>defaults (admin-project WIF pools in for storage, BigQuery and GKE; storage<br/>out). | <pre>object({<br/>    access_policy_name = optional(string)<br/>    perimeter_title    = optional(string)<br/>    enable_dry_run     = optional(bool, true)<br/>    restricted_services = optional(list(string), [<br/>      "bigquery.googleapis.com",<br/>      "storage.googleapis.com",<br/>      "secretmanager.googleapis.com",<br/>      "cloudkms.googleapis.com",<br/>      "pubsub.googleapis.com",<br/>      "sqladmin.googleapis.com",<br/>      "container.googleapis.com",<br/>      "artifactregistry.googleapis.com",<br/>    ])<br/>    dry_run_restricted_services = optional(list(string))<br/>    ingress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      sources = optional(list(object({<br/>        access_level = optional(string)<br/>        resource     = optional(string)<br/>      })))<br/>      resources = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>    egress_policies = optional(list(object({<br/>      identity_type = optional(string)<br/>      identities    = optional(list(string))<br/>      resources     = optional(list(string))<br/>      operations = optional(list(object({<br/>        service_name = string<br/>        method_selectors = optional(list(object({<br/>          method     = optional(string)<br/>          permission = optional(string)<br/>        })))<br/>      })))<br/>    })), [])<br/>  })</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_deploy_workload_identity_provider"></a> [app\_deploy\_workload\_identity\_provider](#output\_app\_deploy\_workload\_identity\_provider) | Full resource name of the app-deploy GitHub WIF provider (google-github-actions/auth `workload_identity_provider`), or null when no service declares `github`. |
| <a name="output_app_github_actions"></a> [app\_github\_actions](#output\_app\_github\_actions) | Per service, the GitHub variables the delivery workflow needs: GCP\_WIF\_PROVIDER, GCP\_DEPLOY\_SA, GCP\_PROJECT\_ID, GCP\_REGION, CLOUD\_RUN\_SERVICE, IMAGE\_REPOSITORY. |
| <a name="output_app_services"></a> [app\_services](#output\_app\_services) | Per app service: Cloud Run url and name, image\_repository, runtime/deploy SA emails, Cloud SQL connection name and IAM DB user (empty when app\_services = {}). |
| <a name="output_components"></a> [components](#output\_components) | Plan-time summary of what the environment creates: budget, cloud\_armor and saas\_secret\_bridge (bool), the keys of vpc\_sc\_perimeters, service\_teams, vm\_backup\_targets, os\_patch\_targets and public\_ingress, and the effective psc\_target. |
| <a name="output_dns_zones"></a> [dns\_zones](#output\_dns\_zones) | DNS zone outputs |
| <a name="output_gke_cluster_name"></a> [gke\_cluster\_name](#output\_gke\_cluster\_name) | Name of the env GKE Autopilot cluster, or null when app\_platform.gke.enabled = false. |
| <a name="output_nat_ip"></a> [nat\_ip](#output\_nat\_ip) | The NAT gateway IP addresses |
| <a name="output_ncc_spoke_id"></a> [ncc\_spoke\_id](#output\_ncc\_spoke\_id) | The environment VPC's NCC spoke ID, or null with hub.connectivity = peering. |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The VPC network ID |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The VPC network name |
| <a name="output_network_self_link"></a> [network\_self\_link](#output\_network\_self\_link) | The VPC network self-link |
| <a name="output_os_patch_deployment_ids"></a> [os\_patch\_deployment\_ids](#output\_os\_patch\_deployment\_ids) | Map of target project key (host, team-<name>) to its VM Manager patch deployment IDs. Empty when vm\_operations.enable\_os\_patch\_management = false. |
| <a name="output_public_ingress"></a> [public\_ingress](#output\_public\_ingress) | Per exposed app service: the global load balancer IP to point the domains' A records at (unless dns\_managed\_zone created them), the domains, and the managed certificate ID. Empty when public ingress is off. |
| <a name="output_saas_secret_id"></a> [saas\_secret\_id](#output\_saas\_secret\_id) | Resource ID of the bridged secret in Secret Manager, or null when saas\_secret\_bridge.enabled is false. |
| <a name="output_security_policy_id"></a> [security\_policy\_id](#output\_security\_policy\_id) | Cloud Armor security policy ID (null when Cloud Armor is disabled) |
| <a name="output_service_team_project_ids"></a> [service\_team\_project\_ids](#output\_service\_team\_project\_ids) | Map of service team name to the created GCP service project ID (empty when no service\_teams are declared). |
| <a name="output_subnets"></a> [subnets](#output\_subnets) | All subnet outputs organized by tier |
| <a name="output_vm_backup_policy_self_links"></a> [vm\_backup\_policy\_self\_links](#output\_vm\_backup\_policy\_self\_links) | Map of target project key (host, team-<name>) to its snapshot-schedule resource policy self\_links. Attach these to persistent disks. Empty when vm\_operations.enable\_backup\_policy = false. |
| <a name="output_vpc_peerings"></a> [vpc\_peerings](#output\_vpc\_peerings) | VPC peering connection outputs |
| <a name="output_vpc_sc_perimeter_names"></a> [vpc\_sc\_perimeter\_names](#output\_vpc\_sc\_perimeter\_names) | Map of VPC-SC perimeter key to perimeter name, or null when VPC-SC is disabled. |
<!-- END_TF_DOCS -->
