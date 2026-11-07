/**
 * Copyright 2023 Ashes
 *
 * Cloud NAT Module - Version Requirements
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
