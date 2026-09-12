# Rulesets

Branch and tag protection as code. GitHub has no mechanism to apply these from
the repository automatically, so they are committed here to be reviewable and
diffable, and applied with `gh`.

## Applying

```shell
gh api -X POST repos/thingzio/actions/rulesets --input .github/rulesets/branch-main.json
gh api -X POST repos/thingzio/actions/rulesets --input .github/rulesets/tag-release.json
```

Updating an existing ruleset needs its id:

```shell
gh api repos/thingzio/actions/rulesets --jq '.[] | "\(.id)\t\(.name)"'
gh api -X PUT repos/thingzio/actions/rulesets/<id> --input .github/rulesets/branch-main.json
```

## Checking for drift

```shell
gh api repos/thingzio/actions/rulesets --jq '.[].name'
gh api repos/thingzio/actions/rulesets/<id> \
  --jq '{name, target, enforcement, rules: [.rules[].type]}'
```

## What each one does, and why

### `branch-main.json`

Protects the default branch.

| Rule | Reason |
|---|---|
| `pull_request`, 1 approval, code-owner review | Every repository in the organization delegates its builds here. Nothing reaches `main` unreviewed. |
| `dismiss_stale_reviews_on_push` | An approval applies to the reviewed commits, not to whatever is pushed afterwards. |
| `require_last_push_approval` | The person who pushed last cannot be the only approver. |
| `required_review_thread_resolution` | An unresolved review comment is unfinished business, not a merge conflict to route around. |
| `required_signatures` | Commit authorship is verifiable, which is the bar `RELEASING.md` also holds tags to. |
| `required_linear_history` + squash-only | `main` stays bisectable. A release must be attributable to one commit. |
| `required_status_checks` with `strict` | `ci` and `selftest` must pass **on the merged result**, not on a stale base. The selftest is the only evidence these workflows actually build and attest. |
| `deletion`, `non_fast_forward` | The branch other repositories pin against cannot be rewritten. |
| Empty `bypass_actors` | Including for the maintainer. A bypass that exists is a bypass that gets used at 2am. |

Status check contexts are the **job names** from `ci.yaml` and `selftest.yaml`.
Renaming a job silently disables its gate — a job that never reports is not a
job that failed — so rename in both places or not at all.

### `tag-release.json`

Makes published versions immutable. `creation` is allowed; `update` and
`deletion` are blocked, so `v1.2.3` can never come to mean different bytes.

The pattern `v*.*.*` matches two dots. The floating major tag `v1` has none, so
it stays movable by `release.yaml` without needing an exclusion rule — which is
why the major tag is named that way rather than `v1.x`.

## Settings not expressible as a ruleset

Apply these once, via the API or the UI:

```shell
# Read-only default token; a job that forgets to elevate is caught immediately.
gh api -X PUT repos/thingzio/actions/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false

# Squash-only, and clean up merged branches.
gh api -X PATCH repos/thingzio/actions \
  -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F allow_squash_merge=true -F delete_branch_on_merge=true \
  -F has_wiki=false -F has_projects=false

# Security features.
gh api -X PATCH repos/thingzio/actions \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'

gh api -X PUT repos/thingzio/actions/vulnerability-alerts
gh api -X PUT repos/thingzio/actions/automated-security-fixes
gh api -X PUT repos/thingzio/actions/private-vulnerability-reporting
```

Fork pull request approval (**Settings → Actions → General → Fork pull request
workflows from outside collaborators**) has no stable API field; set it to
*Require approval for first-time contributors* in the UI. These workflows never
expose a secret to a fork, so this is about compute, not credentials.
