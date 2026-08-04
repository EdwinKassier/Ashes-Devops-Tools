/**
 * Copyright 2023 Ashes
 *
 * Shared VPC Service Project Module - Version Requirements
 */

terraform {
  required_version = "~> 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }
}
