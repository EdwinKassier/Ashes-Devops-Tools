# Function regions are set through resource_config (the deprecated
# serverless_function_region attribute is no longer written).

mock_provider "vercel" {}

variables {
  project_name = "my-app"
  github_repo  = "myorg/my-app"
}

run "default_region_feeds_resource_config" {
  command = plan

  assert {
    condition     = contains(vercel_project.this.resource_config.function_default_regions, "lhr1") && length(vercel_project.this.resource_config.function_default_regions) == 1
    error_message = "The default serverless_function_region (lhr1) must become resource_config.function_default_regions."
  }
}

run "explicit_regions_list_wins" {
  command = plan

  variables {
    function_default_regions = ["iad1", "fra1"]
  }

  assert {
    condition     = length(vercel_project.this.resource_config.function_default_regions) == 2 && contains(vercel_project.this.resource_config.function_default_regions, "fra1")
    error_message = "function_default_regions must override the single-region variable."
  }
}
