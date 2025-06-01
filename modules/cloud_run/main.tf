locals {
  services = {
    "ashes-flask" = {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      port = 8080
    },
    "ashes-django" = {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      port = 8000
    },
    "ashes-fastapi" = {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      port = 8000
    },
    "ashes-express" = {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      port = 8080
    },
    "ashes-hermes" = {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      port = 8080
    }
  }

  # Default environment variables for all services
  default_env_vars = {
    NODE_ENV = var.environment
    PORT     = 8080
  }
}

# Create Cloud Run services
resource "google_cloud_run_v2_service" "service" {
  for_each = local.services

  name     = each.key
  location = var.region
  ingress  = var.ingress_policy
  
  # Use VPC connector if specified
  dynamic "vpc_access" {
    for_each = var.vpc_connector != "" ? [1] : []
    content {
      connector = var.vpc_connector
      egress    = "ALL_TRAFFIC"
    }
  }

  template {
    service_account = var.service_account_email
    
    containers {
      image = each.value.image
      
      # Set resource limits
      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }
      
      # Set environment variables
      dynamic "env" {
        for_each = merge(local.default_env_vars, var.environment_variables, each.value.environment_variables != null ? each.value.environment_variables : {})
        content {
          name  = env.key
          value = env.value
        }
      }
      
      # Configure liveness and readiness probes
      liveness_probe {
        http_get {
          path = var.liveness_path
          port = each.value.port
        }
        initial_delay_seconds = 10
        period_seconds        = 60
        timeout_seconds       = 5
        failure_threshold     = 3
      }
      
      startup_probe {
        http_get {
          path = var.readiness_path
          port = each.value.port
        }
        initial_delay_seconds = 5
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 3
      }
    }
    
    # Configure session affinity
    session_affinity = var.enable_session_affinity
    
    # Configure scaling
    max_instance_request_concurrency = var.max_concurrent_requests
    
    # Configure VPC egress
    vpc_access {
      connector = var.vpc_connector
      egress    = "ALL_TRAFFIC"
    }
  }
  
  # Configure traffic splitting
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  # Add labels
  labels = merge(
    {
      "managed-by" = "terraform"
      "service"    = each.key
    },
    var.labels
  )
}

# Make services private by default
resource "google_cloud_run_service_iam_binding" "no_public" {
  for_each = google_cloud_run_v2_service.service
  
  location = each.value.location
  service  = each.value.name
  role     = "roles/run.invoker"
  members  = ["serviceAccount:${var.service_account_email}"]
}

# Allow additional IAM members if specified
resource "google_cloud_run_service_iam_member" "additional_members" {
  for_each = var.additional_invokers
  
  location = google_cloud_run_v2_service.service[each.key].location
  service  = google_cloud_run_v2_service.service[each.key].name
  role     = "roles/run.invoker"
  member   = each.value
}