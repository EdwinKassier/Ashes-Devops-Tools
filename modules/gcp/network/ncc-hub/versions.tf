/**
 * Copyright 2023 Ashes
 *
 * NCC Hub Module - Provider Versions
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
