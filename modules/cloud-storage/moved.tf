# State migration: hardcoded bucket resources → for_each data_buckets map.
#
# If you were using this module before the data_buckets refactor, add the
# following to your var.data_buckets to match the previous resource names:
#
#   data_buckets = {
#     twitter_data_lake     = { name_suffix = "twitter-data-lake" }
#     twitter_dataflow_meta = { name_suffix = "twitter-dataflow-meta" }
#     looker_data_backup    = { name_suffix = "looker-backup" }
#   }
#
# Then apply once with these moved blocks present to migrate state without
# destroying the buckets. Remove these blocks after the migration is complete.

moved {
  from = google_storage_bucket.twitter_data_lake
  to   = google_storage_bucket.data["twitter_data_lake"]
}

moved {
  from = google_storage_bucket.twitter_dataflow_meta
  to   = google_storage_bucket.data["twitter_dataflow_meta"]
}

moved {
  from = google_storage_bucket.looker_data_backup
  to   = google_storage_bucket.data["looker_data_backup"]
}
