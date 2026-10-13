# Markdown summary of `tofu show -json <plan>`: counts and the address and action of each
# changed resource, no attribute values (the plan holds account and zone IDs, and the PR
# comment it ends up in is public and not masked like the run log).
def action:
  if . == ["create"] then "create"
  elif . == ["update"] then "update"
  elif . == ["delete"] then "destroy"
  elif . == ["delete", "create"] or . == ["create", "delete"] then "replace"
  else join(", ") end;

[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])
  | {address, action: (.change.actions | action)}] as $changes
| [$changes[] | select(.action == "create" or .action == "replace")] as $add
| [$changes[] | select(.action == "update")] as $change
| [$changes[] | select(.action == "destroy" or .action == "replace")] as $destroy
| "### `terraform/cloudflare` plan",
  "",
  if ($changes | length) == 0 then
    "No changes."
  else
    "**\($add | length) to add, \($change | length) to change, \($destroy | length) to destroy.**",
    "",
    "| Resource | Action |",
    "|---|---|",
    ($changes[] | "| `\(.address)` | \(.action) |")
  end,
  if [.output_changes[]? | select(.actions != ["no-op"])] | length > 0 then
    "",
    "Outputs changed: " + ([.output_changes | to_entries[] | select(.value.actions != ["no-op"]) | "`\(.key)`"] | join(", "))
  else empty end
