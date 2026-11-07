/**
 * Copyright 2023 Ashes
 *
 * VPC Flow Logs Export Module - Version Requirements
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
