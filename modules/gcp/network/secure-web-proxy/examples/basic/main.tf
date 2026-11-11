# Example: a hub Secure Web Proxy with an FQDN allowlist, published to two
# spoke projects through Private Service Connect. Replace the placeholder
# values with data sources or remote state in real deployments.

module "secure_web_proxy" {
  source = "../../"

  project_id = "my-hub-project"
  name       = "hub-swp"
  region     = "us-central1"
  network    = "projects/my-hub-project/global/networks/hub-vpc"
  subnetwork = "projects/my-hub-project/regions/us-central1/subnetworks/hub-private"

  allowed_fqdns = ["*.github.com", "registry.npmjs.org", "pypi.org", "files.pythonhosted.org"]

  create_proxy_only_subnet = true
  proxy_only_subnet_cidr   = "10.0.254.0/23"

  create_service_attachment = true
  psc_nat_subnet_cidr       = "10.0.253.0/24"
  consumer_accept_projects  = ["111111111111", "222222222222"]
}
