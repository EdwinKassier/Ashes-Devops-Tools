/**
 * Copyright 2023 Ashes
 *
 * API Gateway Module - Variables
 */

variable "project_id" {
  description = "The ID of the project where the API Gateway will be created"
  type        = string
}

variable "region" {
  description = "The region where the API Gateway will be deployed"
  type        = string
}

variable "api_id" {
  description = "Identifier to use for the API"
  type        = string
  default     = "ashes-api"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,62}$", var.api_id))
    error_message = "api_id must be 4-63 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "display_name" {
  description = "Display name for the API"
  type        = string
  default     = "API Gateway"
}

variable "gateway_id" {
  description = "Identifier to use for this gateway instance"
  type        = string
  default     = "api-gateway"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,62}$", var.gateway_id))
    error_message = "gateway_id must be 4-63 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "gateway_display_name" {
  description = "Display name for the gateway instance"
  type        = string
  default     = "API Gateway Instance"
}

variable "labels" {
  description = "Labels to apply to the API and gateway. A legacy `managed_by` key is accepted and rewritten to the canonical `managed-by`."
  type        = map(string)
  default = {
    environment = "production"
    managed-by  = "terraform"
  }
}

variable "openapi_spec" {
  description = "OpenAPI specification that will be used to configure the API"
  type        = string
  default     = <<EOF
openapi: '3.0.0'
info:
  title: 'API Gateway'
  version: '1.0.0'
paths:
  /health:
    get:
      summary: Health check endpoint
      operationId: health
      responses:
        '200':
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
EOF
}

variable "service_account_email" {
  description = "The service account email to use for the API Gateway backend"
  type        = string
}

variable "managed_service_ids" {
  description = "A map of Service IDs to inject into the OpenAPI spec, replacing the need for external script discovery."
  type        = map(string)
  default     = {}
}
