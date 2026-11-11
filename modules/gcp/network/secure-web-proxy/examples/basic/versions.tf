/**
 * Copyright 2026 Ashes
 *
 * Secure Web Proxy Module - Version Requirements
 */

terraform {
  required_version = ">= 1.17, < 2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}
