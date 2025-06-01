terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 4.0"
    }
  }
}

# Firebase Project
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id
}

# Enable required APIs
resource "google_project_service" "firebase" {
  project = var.project_id
  service = "firebase.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "firestore" {
  project = var.project_id
  service = "firestore.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "identitytoolkit" {
  project = var.project_id
  service = "identitytoolkit.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

# Apple App Resources
resource "google_firebase_apple_app" "default" {
  count        = var.apple_bundle_id != "" ? 1 : 0
  provider     = google-beta
  project      = var.project_id
  display_name = var.apple_display_name
  bundle_id    = var.apple_bundle_id
  app_store_id = var.apple_app_store_id
  team_id      = var.apple_team_id
  api_key_id   = var.apple_bundle_id != "" ? google_apikeys_key.apple[0].uid : ""

  depends_on = [google_firebase_project.default]
}

resource "google_apikeys_key" "apple" {
  count  = var.apple_bundle_id != "" ? 1 : 0
  provider = google-beta

  name         = "${var.apple_bundle_id}-api-key"
  display_name = "${var.apple_display_name} API Key"
  project      = var.project_id

  restrictions {
    ios_key_restrictions {
      allowed_bundle_ids = [var.apple_bundle_id]
    }
  }


  depends_on = [google_firebase_project.default]
}

# Android App Resources
resource "google_firebase_android_app" "default" {
  count         = var.android_package_name != "" ? 1 : 0
  provider      = google-beta
  project       = var.project_id
  display_name  = var.android_display_name
  package_name  = var.android_package_name
  sha1_hashes   = var.android_sha1_hashes
  sha256_hashes = var.android_sha256_hashes

  depends_on = [google_firebase_project.default]
}

# Web App Resources
resource "google_firebase_web_app" "default" {
  count        = var.web_display_name != "" ? 1 : 0
  provider     = google-beta
  project      = var.project_id
  display_name = var.web_display_name

  depends_on = [google_firebase_project.default]
}

data "google_firebase_web_app_config" "default" {
  count      = var.web_display_name != "" ? 1 : 0
  provider   = google-beta
  web_app_id = var.web_display_name != "" ? google_firebase_web_app.default[0].app_id : ""
}

resource "google_storage_bucket" "firebase_web_config" {
  count    = var.web_display_name != "" ? 1 : 0
  provider = google-beta
  name     = "${var.project_id}-firebase-web-config"
  location = var.region
}

resource "google_storage_bucket_object" "firebase_config" {
  count    = var.web_display_name != "" ? 1 : 0
  provider = google-beta
  bucket   = google_storage_bucket.firebase_web_config[0].name
  name     = "firebase-config.json"

  content = jsonencode({
    appId             = google_firebase_web_app.default[0].app_id
    apiKey            = data.google_firebase_web_app_config.default[0].api_key
    authDomain        = data.google_firebase_web_app_config.default[0].auth_domain
    databaseURL       = lookup(data.google_firebase_web_app_config.default[0], "database_url", "")
    storageBucket     = lookup(data.google_firebase_web_app_config.default[0], "storage_bucket", "")
    messagingSenderId = lookup(data.google_firebase_web_app_config.default[0], "messaging_sender_id", "")
    measurementId     = lookup(data.google_firebase_web_app_config.default[0], "measurement_id", "")
  })

  content_type = "application/json"
}
