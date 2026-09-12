#!/usr/bin/env bash
#
# Backs .github/actions/promote-tags.
#
#   IMAGE   full image name including registry, no tag or digest
#   DIGEST  attested index digest to point the tags at
#   TAGS    newline-separated tags to publish
#
# This is the last step of a build and the only one that makes an image
# reachable by name. Everything before it published to a run-unique candidate
# tag, so a failed attestation cannot leave a released tag pointing at unsigned
# bytes. `crane tag` re-points a tag at an existing manifest without moving any
# layers, so promotion is a registry-side metadata change and a re-run produces
# the same result rather than a second upload with a new digest.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

OCI_TAG_PATTERN='^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$'

main() {
  local image="${IMAGE-}" digest="${DIGEST-}" tags="${TAGS-}"
  local tag published=""

  require_set image "${image}"
  require_set digest "${digest}"
  require_set tags "${tags}"
  require_no_newline image "${image}"
  require_no_newline digest "${digest}"

  [[ "${digest}" =~ ^sha256:[a-f0-9]{64}$ ]] ||
    die "digest must be of the form sha256:<64 lowercase hex>, got '${digest}'"

  while IFS= read -r tag; do
    [ -n "${tag}" ] || continue
    # Re-validated rather than trusted: this action is public and may be used
    # outside the reusable workflows, where nothing upstream has checked the
    # tag grammar.
    [[ "${tag}" =~ ${OCI_TAG_PATTERN} ]] || die "'${tag}' is not a valid OCI tag"

    timeout --foreground 120s crane tag "${image}@${digest}" "${tag}"
    notice "published ${image}:${tag} -> ${digest}"
    published="${published}- \`${image}:${tag}\`"$'\n'
  done <<<"${tags}"

  {
    printf '### Published\n\n'
    # Backticks are markdown for the job summary, not command substitution.
    # shellcheck disable=SC2016
    printf 'Digest: `%s`\n\n' "${digest}"
    printf '%s\n' "${published}"
    printf 'Pull by digest to get exactly what was attested:\n\n'
    printf '    docker pull %s@%s\n\n' "${image}" "${digest}"
  } >>"${GITHUB_STEP_SUMMARY}"
}

main "$@"
