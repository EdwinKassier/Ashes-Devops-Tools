/**
 * Copyright 2023 Ashes
 *
 * VPC Flow Logs Export Module - Version Requirements
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
