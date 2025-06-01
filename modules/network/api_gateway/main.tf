/**
 * Copyright 2023 Ashes
 *
 * API Gateway Module - Main Configuration
 */

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

# API Gateway API resource
resource "google_api_gateway_api" "api" {
  provider = google
  project  = var.project_id
  api_id   = var.api_id
  display_name = var.display_name
  labels   = var.labels
}

# API Config resource
resource "google_api_gateway_api_config" "api_config" {
  provider      = google
  project       = var.project_id
  api           = google_api_gateway_api.api.api_id
  api_config_id = "${var.api_id}-config-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  display_name  = "${var.display_name} Config"
  
  openapi_documents {
    document {
      path     = "spec.yaml"
      contents = base64encode(var.openapi_spec)
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
  provider     = google
  project      = var.project_id
  region       = var.region
  api_config   = google_api_gateway_api_config.api_config.id
  gateway_id   = var.gateway_id
  display_name = var.gateway_display_name
  
  labels       = var.labels
} 