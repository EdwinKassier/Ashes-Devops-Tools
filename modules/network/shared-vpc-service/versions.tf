/**
 * Copyright 2023 Ashes
 *
 * Shared VPC Service Project Module - Version Requirements
 */

terraform {
  required_version = ">= 1.3"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}
