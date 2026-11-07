/**
 * Copyright 2023 Ashes
 *
 * Shared VPC Service Project Module - Version Requirements
 */

terraform {
  required_version = ">= 1.17, < 2.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}
