# Scrub a `terraform show -json <planfile>` document into an OPA test fixture
# in the HCP Terraform policy input shape ({plan: {...}}; no run, since no
# policy may trust input.run).
#
#   terraform show -json plan.tfplan | jq -f policies/opa/tests/fixtures/scrub.jq > fixture.json
#
# Kept: resource_changes[].{address, module_address, mode, type, name} and
# change.{actions, after, after_unknown} (the attributes the policies read).
# change.after holds sensitive values in PLAINTEXT (after_sensitive is only the
# mask), so every path the mask marks true is replaced by "(sensitive)" first
# (a mask of true on the whole object replaces the whole object).
# Dropped: change.before, before_sensitive, after_sensitive (after masking),
# prior state, configuration, variables and outputs; and, at any depth of after /
# after_unknown, every identifier key (id, arn, *_id, *_arn, *_ids,
# self_link, etag, number, unique_id, owner_id). Review every fixture by eye
# before committing: free-text attributes (policies, labels, descriptions)
# are kept because policies read them. Only scrubbed sandbox plans are
# committed; never raw plan JSON. No policy reads an identifier attribute
# today; one that starts to must be exempted in id_key.

def id_key:
  test("^(id|arn|etag|self_link|number|unique_id|owner_id)$|(_id|_ids|_arn|_arns)$");

# Replace every value the sensitivity mask marks true. Walks the value and the
# mask together: objects by key, lists by index.
def mask($m):
  if $m == true then
    "(sensitive)"
  elif type == "object" and ($m | type) == "object" then
    with_entries(.key as $k | .value |= mask($m[$k]))
  elif type == "array" and ($m | type) == "array" then
    [to_entries[] | .key as $i | .value | mask($m[$i])]
  else
    .
  end;

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
            after: ((.change.after_sensitive // false) as $m | .change.after | mask($m) | drop_ids),
            after_unknown: (.change.after_unknown | drop_ids)
          }
        }
      | with_entries(select(.value != null))
    ]
  }
}
