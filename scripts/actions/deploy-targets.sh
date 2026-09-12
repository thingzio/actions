#!/usr/bin/env bash
#
# Validates the deployment targets of .github/workflows/deploy-cloud-run.yaml
# and rewrites each image onto the Artifact Registry remote repository.
#
#   TARGETS            newline-separated "<kind>=<name>=<image-ref>" entries
#   EXPECTED_REGISTRY  registry the images must have been published to
#   REGION             Cloud Run / Artifact Registry region
#   PROJECT_ID         GCP project holding the remote repository
#   REMOTE_REPOSITORY  name of the Artifact Registry remote repository
#
# Emits to GITHUB_OUTPUT:
#
#   plan   one "<kind> <name> <rewritten-image>" line per target, order preserved
#   count  number of targets
#
# THIS IS THE TRUST BOUNDARY FOR A PRODUCTION DEPLOY.
#
# Every value here reaches a gcloud command line. Three rules follow:
#
#   1. A tag is never accepted. Only <registry>/<repo>@sha256:<64 hex>. A tag
#      can move between the build and the deploy, and then the thing that was
#      tested is not the thing that ships.
#
#   2. The registry is checked against where the build publishes, not against
#      the path Cloud Run pulls from. Anchoring the check to the source is what
#      makes it mean anything; the rewrite below is a path change, not a copy.
#
#   3. Resource names are matched against the Cloud Run grammar, so a name can
#      never introduce a flag, a space or a shell metacharacter.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

: "${EXPECTED_REGISTRY:=ghcr.io}"
: "${REMOTE_REPOSITORY:=gh}"

# Cloud Run resource names: lowercase alphanumeric and hyphens, starting with a
# letter, at most 63 characters.
NAME_PATTERN='^[a-z]([-a-z0-9]*[a-z0-9])?$'

# A digest reference, with the repository path constrained to the OCI grammar.
DIGEST_PATTERN='^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*@sha256:[0-9a-f]{64}$'

validate_kind() {
  case "$1" in
    service | job) printf '%s' "$1" ;;
    *) die "unknown target kind '$1'; expected 'service' or 'job'" ;;
  esac
}

validate_name() {
  local name="$1"
  [ "${#name}" -le 63 ] || die "resource name is longer than 63 characters: ${name}"
  [[ "${name}" =~ ${NAME_PATTERN} ]] ||
    die "invalid Cloud Run resource name '${name}'"
  printf '%s' "${name}"
}

# to_remote validates an image reference and rewrites it onto the remote
# repository. The doubled organization segment in the result is correct: the
# remote repository is common-upstream, so the full upstream path including the
# organization follows the repository name.
to_remote() {
  local ref="$1" name="$2" host path

  case "${ref}" in
    "${EXPECTED_REGISTRY}/"*) ;;
    *) die "${name}: image must be published to ${EXPECTED_REGISTRY}, got '${ref}'" ;;
  esac

  path="${ref#"${EXPECTED_REGISTRY}/"}"
  [[ "${path}" =~ ${DIGEST_PATTERN} ]] ||
    die "${name}: expected ${EXPECTED_REGISTRY}/<repository>@sha256:<64 hex>, got '${ref}'"

  host="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REMOTE_REPOSITORY}"
  printf '%s/%s' "${host}" "${path}"
}

main() {
  local line kind name ref plan="" count=0

  require_set region "${REGION-}"
  require_set project_id "${PROJECT_ID-}"
  require_set targets "${TARGETS-}"

  while IFS= read -r line; do
    # Trim, and skip blanks and comments so a caller can annotate the list.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "${line}" ] || continue
    case "${line}" in \#*) continue ;; esac

    IFS='=' read -r kind name ref <<<"${line}"
    [ -n "${kind}" ] && [ -n "${name}" ] && [ -n "${ref}" ] ||
      die "malformed target '${line}'; expected <service|job>=<name>=<image@digest>"

    kind="$(validate_kind "${kind}")"
    name="$(validate_name "${name}")"
    ref="$(to_remote "${ref}" "${name}")"

    plan="${plan}${kind} ${name} ${ref}"$'\n'
    count=$((count + 1))
  done <<<"${TARGETS}"

  [ "${count}" -gt 0 ] || die "no deployment targets were given"

  log "validated ${count} deployment target(s)"
  printf '%s' "${plan}" | while IFS= read -r line; do log "  ${line}"; done

  emit_multiline_output plan "${plan%$'\n'}"
  emit_output count "${count}"
}

main "$@"
