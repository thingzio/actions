#!/usr/bin/env bash
#
# Derives the image tags for a build from the GitHub event context.
#
#   scripts/derive-tags.sh release     # the tags to publish (default)
#   scripts/derive-tags.sh candidate   # the run-unique staging tag
#
# Reads its input from the environment rather than from arguments so a caller
# cannot smuggle a second tag through argument splitting:
#
#   TAGS_OVERRIDE    caller-supplied tags; replaces the derived set entirely
#   EVENT_NAME       github.event_name
#   REF_TYPE         github.ref_type ("branch" or "tag")
#   REF_NAME         github.ref_name
#   SHA              github.sha
#   PR_NUMBER        github.event.pull_request.number
#   DEFAULT_BRANCH   github.event.repository.default_branch
#   RUN_ID           github.run_id        (candidate mode)
#   RUN_ATTEMPT      github.run_attempt   (candidate mode)
#
# Writes one tag per line to stdout. Every tag, derived or caller-supplied, is
# validated against the OCI tag grammar before it is printed, so nothing
# downstream has to re-check it.
#
# Why a candidate tag exists: builds publish to a run-unique tag first, and the
# release tags are moved onto the resulting digest only after attestation
# succeeds. A failed signing step therefore never leaves a published `latest`.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# An OCI tag is at most 128 characters and may not begin with "." or "-".
OCI_TAG_PATTERN='^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$'

# sanitize_tag rewrites a git ref into something usable as an OCI tag. Branch
# names routinely contain "/" (feature/foo) which is not legal in a tag.
sanitize_tag() {
  local value
  value="$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-')"
  value="${value:0:128}"
  case "${value}" in
    [A-Za-z0-9_]*) ;;
    *) value="x${value}" ;;
  esac
  printf '%s' "${value}"
}

# normalize_list splits a comma- or newline-separated list into one entry per
# line, dropping whitespace, empties and duplicates while preserving order.
normalize_list() {
  tr ',' '\n' | awk '{ gsub(/[[:space:]]/, ""); if ($0 != "" && !seen[$0]++) print }'
}

# print_validated emits each line of a newline-separated list after checking it
# against the OCI tag grammar. Iterating with IFS rather than piping into a
# `while read` loop matters: a pipeline runs in a subshell, where die() would
# exit the subshell and let the caller carry on with a bad tag.
print_validated() {
  local list="$1" saved_ifs="${IFS}" tag
  IFS='
'
  set -f
  for tag in ${list}; do
    [[ "${tag}" =~ ${OCI_TAG_PATTERN} ]] ||
      die "'${tag}' is not a valid OCI tag (max 128 chars of A-Za-z0-9._- not starting with . or -)"
    printf '%s\n' "${tag}"
  done
  set +f
  IFS="${saved_ifs}"
}

derive_candidate() {
  case "${RUN_ID-}" in
    "" | *[!0-9]*) die "RUN_ID must be numeric, got '${RUN_ID-}'" ;;
  esac
  case "${RUN_ATTEMPT-}" in
    "" | *[!0-9]*) die "RUN_ATTEMPT must be numeric, got '${RUN_ATTEMPT-}'" ;;
  esac
  printf 'candidate-%s-%s\n' "${RUN_ID}" "${RUN_ATTEMPT}"
}

derive_release() {
  local tags ref major minor

  if [ -n "${TAGS_OVERRIDE-}" ]; then
    tags="$(printf '%s\n' "${TAGS_OVERRIDE}" | normalize_list)"
    [ -n "${tags}" ] || die "the tags input was set but contained no usable tag"
    printf '%s\n' "${tags}"
    return 0
  fi

  if [ "${REF_TYPE-}" = "tag" ]; then
    ref="${REF_NAME-}"
    require_set REF_NAME "${ref}"

    # A release tag fans out to the moving major and minor aliases and latest.
    # A prerelease deliberately does not: v1.2.3-rc.1 must never become the
    # thing `latest` or `v1` resolves to.
    if [[ "${ref}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      major="v${BASH_REMATCH[1]}"
      minor="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
      printf '%s\n%s\n%s\n%s\n' "${ref}" "${minor}" "${major}" "latest"
      return 0
    fi

    printf '%s\n' "$(sanitize_tag "${ref}")"
    return 0
  fi

  if [ "${EVENT_NAME-}" = "pull_request" ]; then
    case "${PR_NUMBER-}" in
      "" | *[!0-9]*) die "pull_request events require a numeric PR_NUMBER, got '${PR_NUMBER-}'" ;;
    esac
    printf 'pr-%s\n' "${PR_NUMBER}"
    return 0
  fi

  # Branch push. The short SHA is always emitted because it is the only tag
  # guaranteed to be unique; the branch name is added on the default branch so
  # that `:main` tracks the tip.
  case "${SHA-}" in
    *[!0-9a-f]* | "") die "expected a 40-character lowercase commit SHA, got '${SHA-}'" ;;
  esac
  [ "${#SHA}" = "40" ] || die "expected a 40-character commit SHA, got '${SHA}'"

  printf 'sha-%s\n' "${SHA:0:7}"
  if [ -n "${DEFAULT_BRANCH-}" ] && [ "${REF_NAME-}" = "${DEFAULT_BRANCH}" ]; then
    printf '%s\n' "$(sanitize_tag "${DEFAULT_BRANCH}")"
  fi
}

main() {
  local mode="${1:-release}"
  case "${mode}" in
    release) print_validated "$(derive_release)" ;;
    candidate) print_validated "$(derive_candidate)" ;;
    *) die "unknown mode '${mode}'; expected 'release' or 'candidate'" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
