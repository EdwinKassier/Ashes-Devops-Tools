/**
 * Copyright 2023 Ashes
 *
 * API Gateway Module - Main Configuration
 */


locals {
  # Use provided OpenAPI spec, with optional template substitution if managed_service_ids is provided
  openapi_content = length(var.managed_service_ids) > 0 ? templatefile("${path.module}/templates/openapi.yaml.tftpl", {
    services     = var.managed_service_ids
    display_name = var.display_name
  }) : var.openapi_spec
}

# API Gateway API resource
resource "google_api_gateway_api" "api" {
  provider     = google-beta
  project      = var.project_id
  api_id       = var.api_id
  display_name = var.display_name
  labels       = var.labels
}

# API Config resource
resource "google_api_gateway_api_config" "api_config" {
  provider      = google-beta
  project       = var.project_id
  api           = google_api_gateway_api.api.api_id
  api_config_id = "${var.api_id}-config-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  display_name  = "${var.display_name} Config"

  openapi_documents {
    document {
      path     = "spec.yaml"
      contents = base64encode(local.openapi_content)
    }
  }

  gateway_config {
    backend_config {
      google_service_account = var.service_account_email
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway resource
resource "google_api_gateway_gateway" "gateway" {
  provider     = google-beta
  project      = var.project_id
  region       = var.region
  api_config   = google_api_gateway_api_config.api_config.id
  gateway_id   = var.gateway_id
  display_name = var.gateway_display_name

  labels = var.labels
}

# Serverless NEG for Load Balancer integration
resource "google_compute_region_network_endpoint_group" "serverless_neg" {
  provider              = google-beta
  name                  = "${var.gateway_id}-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  project               = var.project_id

  serverless_deployment {
    platform = "apigateway.googleapis.com"
    resource = google_api_gateway_gateway.gateway.gateway_id
  }
} 