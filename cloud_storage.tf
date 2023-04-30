resource "google_storage_bucket" "twitter_data_lake" {
  name                        = "twitter_data_lake"
  location                    = "MULTI_REGIONAL"
  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket" "twitter_dataflow_meta" {
  name                        = "twitter_dataflow_meta"
  location                    = "MULTI_REGIONAL"
  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}


resource "google_storage_bucket" "looker_data_backup" {
  name                        = "looker_data_backup"
  location                    = "MULTI_REGIONAL"
  force_destroy               = true
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}