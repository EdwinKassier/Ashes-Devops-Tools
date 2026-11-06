# Scrub a `terraform show -json <planfile>` document into an OPA test fixture
# in the HCP Terraform policy input shape ({plan: {...}}; no run, since no
# policy may trust input.run).
#
#   terraform show -json plan.tfplan | jq -f policies/opa/tests/fixtures/scrub.jq > fixture.json
#
# Kept: resource_changes[].{address, module_address, mode, type, name} and
# change.{actions, after, after_unknown} (the attributes the policies read).
# Dropped: change.before, change.after_sensitive, before_sensitive, prior
# state, configuration, variables and outputs; and, at any depth of after /
# after_unknown, every identifier key (id, arn, *_id, *_arn, *_ids,
# self_link, etag, number, unique_id, owner_id). Review every fixture by eye
# before committing: free-text attributes (policies, labels, descriptions)
# are kept because policies read them. Only scrubbed sandbox plans are
# committed; never raw plan JSON. No policy reads an identifier attribute
# today; one that starts to must be exempted in id_key.

def id_key:
  test("^(id|arn|etag|self_link|number|unique_id|owner_id)$|(_id|_ids|_arn|_arns)$");

def drop_ids:
  if type == "object" then
    with_entries(select(.key | id_key | not) | .value |= drop_ids)
  elif type == "array" then
    map(drop_ids)
  else
    .
  end;

{
  plan: {
    format_version: .format_version,
    resource_changes: [
      (.resource_changes // [])[]
      | {
          address,
          module_address,
          mode,
          type,
          name,
          change: {
            actions: .change.actions,
            after: (.change.after | drop_ids),
            after_unknown: (.change.after_unknown | drop_ids)
          }
        }
      | with_entries(select(.value != null))
    ]
  }
}
