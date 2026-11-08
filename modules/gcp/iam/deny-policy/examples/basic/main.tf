# Example: an IAM deny policy on a workloads folder that blocks service-account
# key creation and upload for every principal except a break-glass group, and
# blocks project deletion everywhere in the folder. Deny is evaluated before
# allow, so these hold whatever roles a principal has been granted.
#
# The applying identity needs roles/iam.denyAdmin on the folder. Replace the
# placeholder folder ID and group before use.
#
# Run `terraform init && terraform validate` here.

module "folder_deny" {
  source = "../../"

  # URL-encoded attachment point: build it with urlencode(...).
  parent = urlencode("cloudresourcemanager.googleapis.com/folders/123456789012")

  deny_policies = [
    {
      name         = "workloads-guardrails"
      display_name = "Workloads folder guardrails"
      rules = [
        {
          description       = "Only break-glass may create or upload service-account keys"
          denied_principals = ["principalSet://goog/public:all"]
          denied_permissions = [
            "iam.googleapis.com/serviceAccountKeys.create",
            "iam.googleapis.com/serviceAccountKeys.upload",
          ]
          exception_principals = [
            "principalSet://goog/group/break-glass@example.com",
          ]
        },
        {
          description          = "Only break-glass may delete projects"
          denied_principals    = ["principalSet://goog/public:all"]
          denied_permissions   = ["cloudresourcemanager.googleapis.com/projects.delete"]
          exception_principals = ["principalSet://goog/group/break-glass@example.com"]
        },
      ]
    },
  ]
}
