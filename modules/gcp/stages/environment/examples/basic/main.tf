# Example: one dev application environment, composed (what a
# gcp-workload-<env> workspace deploys). In the Shared VPC host project it
# creates the spoke VPC (tiered subnets, NAT, Private Service Access, PSC) peered
# to the hub, a VPC-SC perimeter in dry-run, a Cloud Armor policy, a monthly
# budget, daily VM snapshots and weekly OS patching, one service-team project,
# and one internal-only Cloud Run service with a private-IP Cloud SQL database
# and a GitHub Actions deploy identity.
#
# In a real deployment envs/gcp/workload resolves these values from
# config/landing-zone.yaml and the gcp-organization, gcp-projects and
# gcp-network-hub remote state. The host project, hub network, access policy,
# KMS keys and secret must already exist. Replace the placeholder values before use.
#
# Run `terraform init && terraform validate` here.

module "environment" {
  source = "../../"

  environment     = "dev"
  project_prefix  = "acme"
  org_id          = "123456789012"
  billing_account = "000000-111111-222222"

  host_project = {
    project_id     = "acme-dev-host-abcd"
    project_number = "222222222222"
    folder_id      = "folders/333333333333"
    region         = "europe-west2"
    cidr_block     = "10.10.0.0/16"
  }

  hub = {
    connectivity = "peering"
    peerings = {
      hub-peering = {
        peer_network         = "https://www.googleapis.com/compute/v1/projects/acme-hub-project/global/networks/acme-hub-vpc"
        export_custom_routes = true
        import_custom_routes = true
      }
    }
  }

  cloud_armor = {
    enabled     = true
    owasp_rules = true
  }

  # Start in dry-run; flip enable_dry_run to false once the violation logs are clean.
  vpc_service_controls = {
    access_policy_name = "123456789" # bare numeric access policy ID
    enable_dry_run     = true
  }

  budget = {
    monthly_limit = 500
    currency      = "USD"
  }

  service_teams = {
    payments = {
      project_admin_group_email = "payments-admins@example.com"
      activate_apis             = ["run.googleapis.com"]
      shared_vpc_subnets = {
        # Subnets are named <vpc>-<tier>-<zone>.
        private = { region = "europe-west2", subnet_name = "acme-dev-vpc-private-europe-west2-a" }
      }
    }
  }

  app_platform = {
    artifact_registry_kms_key_name = "projects/acme-kms-project/locations/europe-west2/keyRings/dev-keyring/cryptoKeys/artifact-registry"
    enable_deploy_wif              = true
    github_repository_owner_id     = "12345678" # gh api orgs/<org> --jq .id
  }

  # Validated by gcp/stages/app-services; ingress defaults to internal only.
  app_services = {
    orders-api = {
      secrets = {
        STRIPE_API_KEY = { secret = "orders-api-stripe-key" }
      }
      database = {
        databases           = ["orders"]
        encryption_key_name = "projects/acme-kms-project/locations/europe-west2/keyRings/dev-keyring/cryptoKeys/cloudsql"
      }
      github = {
        repository_id = "987654321" # gh api repos/<owner>/<repo> --jq .id
        ref           = "refs/heads/main"
      }
    }
  }

  labels = {
    environment = "dev"
    managed-by  = "terraform"
  }
}
