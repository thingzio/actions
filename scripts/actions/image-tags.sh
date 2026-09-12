#!/usr/bin/env bash
#
# Backs .github/actions/image-tags. Publishes the release tag set, the primary
# tag and the run-unique candidate tag as step outputs.
#
# Reads the same environment scripts/derive-tags.sh documents. Nothing is
# interpolated into a shell body, so a branch named `$(id)` stays data.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

main() {
  local tags candidate primary

  tags="$("${REPO_ROOT}/scripts/derive-tags.sh" release)"
  candidate="$("${REPO_ROOT}/scripts/derive-tags.sh" candidate)"
  primary="$(printf '%s\n' "${tags}" | head -1)"

  emit_multiline_output tags "${tags}"
  emit_output primary_tag "${primary}"
  emit_output candidate_tag "${candidate}"

  {
    printf '### Tags\n\n'
    # Backticks are markdown for the job summary, not command substitution.
    # shellcheck disable=SC2016
    printf 'Candidate: `%s`\n\n' "${candidate}"
    printf 'Release tags:\n\n'
    # shellcheck disable=SC2016
    printf '%s\n' "${tags}" | sed 's/^/- `/; s/$/`/'
    printf '\n'
  } >>"${GITHUB_STEP_SUMMARY}"
}

main "$@"
