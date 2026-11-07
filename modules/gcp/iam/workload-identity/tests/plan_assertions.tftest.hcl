# Plan assertions for the iam/workload-identity module: verify the WIF pool is planned
# with the caller-supplied id and display name.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  pool_id      = "test-pool"
  display_name = "Test Pool"
}

run "pool_wired" {
  command = plan

  assert {
    condition     = google_iam_workload_identity_pool.pool.workload_identity_pool_id == var.pool_id
    error_message = "WIF pool id must be the caller-supplied pool_id."
  }

  assert {
    condition     = google_iam_workload_identity_pool.pool.display_name == var.display_name
    error_message = "WIF pool display name must be the caller-supplied display_name."
  }

  assert {
    condition     = google_iam_workload_identity_pool.pool.project == var.project_id
    error_message = "WIF pool must be created in the caller-supplied project."
  }
}

# The GitLab trust matches the namespace or its sub-groups only, never a
# sibling group that merely shares the prefix ("acme" must not trust "acme-evil").
run "gitlab_namespace_is_not_a_prefix_match" {
  command = plan

  variables {
    enable_gitlab_provider = true
    gitlab_namespace       = "acme/"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.gitlab[0].attribute_condition == "assertion.namespace_path == 'acme' || assertion.namespace_path.startsWith('acme/')"
    error_message = "GitLab attribute_condition must be namespace_path == X || startsWith(X/), not a bare prefix."
  }
}

# The GitHub provider condition is ONLY the canonical owner pin, in the exact
# double-quoted form the org-policy tenant constraint compares against. Repo,
# ref and environment are pinned by the bindings, never by the condition.
run "computed_condition_is_owner_only" {
  command = plan

  variables {
    enable_github_provider     = true
    github_repository_owner_id = "1111"
    github_allowed_refs        = ["refs/heads/main"]
    github_sa_bindings = [
      {
        repository            = "acme/infra"
        repository_id         = "2222"
        service_account_email = "gh-deploy@mock-project.iam.gserviceaccount.com"
      },
    ]
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.github[0].attribute_condition == "assertion.repository_owner_id == \"1111\""
    error_message = "the GitHub attribute_condition must be exactly assertion.repository_owner_id == \"<id>\"."
  }

  assert {
    condition     = output.github_attribute_condition == "assertion.repository_owner_id == \"1111\""
    error_message = "github_attribute_condition must report the canonical condition."
  }

  assert {
    condition = (
      google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repo_ref"] == "assertion.repository_id + '/' + assertion.ref" &&
      google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repo_env"] == "assertion.repository_id + '/' + (has(assertion.environment) ? assertion.environment : '-')" &&
      google_iam_workload_identity_pool_provider.github[0].attribute_mapping["attribute.repo_ref_env"] == "assertion.repository_id + '/' + assertion.ref + '/' + (has(assertion.environment) ? assertion.environment : '-')"
    )
    error_message = "the provider must map the repo_ref, repo_env and repo_ref_env composite attributes."
  }
}

# github_allowed_refs keeps its branch restriction by binding each allowed ref
# through attribute.repo_ref ("<repository_id>/<ref>").
run "allowed_refs_bind_repo_ref" {
  command = plan

  override_resource {
    target          = google_iam_workload_identity_pool.pool
    override_during = plan
    values = {
      name = "projects/1/locations/global/workloadIdentityPools/test-pool"
    }
  }

  variables {
    enable_github_provider     = true
    github_repository_owner_id = "1111"
    github_allowed_refs        = ["refs/heads/main", "refs/tags/v1"]
    github_sa_bindings = [
      {
        repository            = "acme/infra"
        repository_id         = "2222"
        key                   = "deploy"
        service_account_email = "gh-deploy@mock-project.iam.gserviceaccount.com"
      },
    ]
  }

  assert {
    condition = (
      length(google_service_account_iam_member.github_workload_identity) == 2 &&
      google_service_account_iam_member.github_workload_identity["deploy:refs/heads/main"].member == "principalSet://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/test-pool/attribute.repo_ref/2222/refs/heads/main" &&
      google_service_account_iam_member.github_workload_identity["deploy:refs/tags/v1"].member == "principalSet://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/test-pool/attribute.repo_ref/2222/refs/tags/v1"
    )
    error_message = "each allowed ref must get its own attribute.repo_ref/<repository_id>/<ref> binding."
  }
}

# One allowed ref keeps the binding's existing for_each key, so callers such as
# gcp-bootstrap (refs/heads/main only) do not move state addresses.
run "single_allowed_ref_keeps_binding_key" {
  command = plan

  override_resource {
    target          = google_iam_workload_identity_pool.pool
    override_during = plan
    values = {
      name = "projects/1/locations/global/workloadIdentityPools/test-pool"
    }
  }

  variables {
    enable_github_provider     = true
    github_repository_owner_id = "1111"
    github_allowed_refs        = ["refs/heads/main"]
    github_sa_bindings = [
      {
        repository            = "acme/infra"
        repository_id         = "2222"
        key                   = "organization-plan"
        service_account_email = "gh-deploy@mock-project.iam.gserviceaccount.com"
      },
    ]
  }

  assert {
    condition     = keys(google_service_account_iam_member.github_workload_identity) == ["organization-plan"] && endswith(google_service_account_iam_member.github_workload_identity["organization-plan"].member, "/attribute.repo_ref/2222/refs/heads/main")
    error_message = "a single allowed ref must keep the binding key and bind attribute.repo_ref."
  }
}

# Without github_allowed_refs the binding stays on the immutable repository_id.
run "no_allowed_refs_bind_repository_id" {
  command = plan

  override_resource {
    target          = google_iam_workload_identity_pool.pool
    override_during = plan
    values = {
      name = "projects/1/locations/global/workloadIdentityPools/test-pool"
    }
  }

  variables {
    enable_github_provider     = true
    github_repository_owner_id = "1111"
    github_sa_bindings = [
      {
        repository            = "acme/infra"
        repository_id         = "2222"
        key                   = "deploy"
        service_account_email = "gh-deploy@mock-project.iam.gserviceaccount.com"
      },
    ]
  }

  assert {
    condition     = keys(google_service_account_iam_member.github_workload_identity) == ["deploy"] && endswith(google_service_account_iam_member.github_workload_identity["deploy"].member, "/attribute.repository_id/2222")
    error_message = "without github_allowed_refs the binding must stay on attribute.repository_id."
  }
}
