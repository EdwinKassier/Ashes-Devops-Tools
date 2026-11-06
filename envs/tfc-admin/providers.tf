# The tfe provider authenticates with a TFC team/user token supplied out-of-band
# (TFE_TOKEN env var or a credentials block). This root manages ONLY the TFC
# workspace layer; it declares no cloud provider, so it pulls in no cloud
# credentials (the any-combination property holds).
provider "tfe" {
  organization = local.tfc_organization
}
