# shellcheck shell=bash
#
# Common preamble for the scripts that back the composite actions in
# .github/actions. Source it first; it locates the repository root, pulls in the
# shared helpers, and makes the Actions-provided files safe to write to when a
# script is run outside a workflow.
#
# These scripts live under scripts/ rather than inside the action.yml `run:`
# blocks they replace for one reason: shell embedded in an action.yml is linted
# by nothing. actionlint checks workflows, not composite actions, and a glob
# over .sh files cannot reach inside YAML. Moving the logic here puts it under
# `make lint-shell` and makes it directly testable.

ACTION_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${ACTION_LIB_DIR}/../.." && pwd)"
export REPO_ROOT

# shellcheck source=scripts/lib/common.sh
. "${REPO_ROOT}/scripts/lib/common.sh"

# Outside a workflow these are unset. Defaulting them keeps the scripts runnable
# for debugging without special-casing every write.
: "${GITHUB_OUTPUT:=/dev/null}"
: "${GITHUB_STEP_SUMMARY:=/dev/null}"
export GITHUB_OUTPUT GITHUB_STEP_SUMMARY
