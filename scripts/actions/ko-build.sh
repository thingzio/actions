#!/usr/bin/env bash
#
# Builds the ko command line and runs it.
#
#   KO_DOCKER_REPO  full image name including registry, no tag
#   MAIN            Go main package path, e.g. ./cmd/app
#   PLATFORMS       comma-separated platform list
#   CANDIDATE_TAG   run-unique staging tag to push to
#   PRIMARY_TAG     first release tag, used for the version label
#   EXTRA_LABELS    caller labels, one key=value per line
#   KO_FLAGS        allowlisted extra ko flags, one per line
#   PUSH            "true" to publish
#   SOURCE_URL      repository URL for the source label
#   REVISION        commit SHA for the revision label
#   CREATED         optional RFC 3339 timestamp; defaults to now
#
#   KO_ARGS_ONLY    when set, print the argument vector and exit without
#                   running ko. This is what makes the quoting below testable.
#
# This lives in a script rather than inline in the workflow because the argument
# construction has a genuine sharp edge, and inline YAML is linted by nothing
# and testable by nothing. The sharp edge:
#
#   ko's --image-label is a pflag string slice, which parses each value with
#   encoding/csv. A label whose value contains a comma -- which a description
#   routinely does -- is torn into fragments, and ko rejects the remainder with
#   "invalid label flag: <fragment>". Wrapping the whole key=value in double
#   quotes, with any embedded quote doubled per CSV rules, passes it through
#   intact. This was found by the selftest failing on its own fixture labels.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# csv_quote wraps a value so ko's CSV slice parser treats it as one field.
csv_quote() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')"
}

build_args() {
  local label flag created

  require_set main "${MAIN-}"
  require_no_newline main "${MAIN}"
  case "${MAIN}" in
    -*) die "main must be a package path, not a flag: '${MAIN}'" ;;
  esac

  created="${CREATED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

  # An array, so no value is ever re-split or glob-expanded by the shell.
  KO_ARGS=(build "${MAIN}" --bare
    "--platform=${PLATFORMS}"
    "--tags=${CANDIDATE_TAG}")

  KO_ARGS+=("--image-label=$(csv_quote "org.opencontainers.image.source=${SOURCE_URL-}")")
  KO_ARGS+=("--image-label=$(csv_quote "org.opencontainers.image.revision=${REVISION-}")")
  KO_ARGS+=("--image-label=$(csv_quote "org.opencontainers.image.version=${PRIMARY_TAG-}")")
  KO_ARGS+=("--image-label=$(csv_quote "org.opencontainers.image.created=${created}")")

  while IFS= read -r label; do
    [ -n "${label}" ] || continue
    KO_ARGS+=("--image-label=$(csv_quote "${label}")")
  done <<<"${EXTRA_LABELS-}"

  while IFS= read -r flag; do
    [ -n "${flag}" ] || continue
    KO_ARGS+=("${flag}")
  done <<<"${KO_FLAGS-}"

  # A fork pull request has no registry credential. ko still cross-compiles
  # every requested platform and resolves the index locally, so the build is
  # genuinely validated; it just publishes nothing.
  if [ "${PUSH-}" != "true" ]; then
    KO_ARGS+=(--push=false)
  fi
}

main() {
  build_args

  if [ -n "${KO_ARGS_ONLY-}" ]; then
    printf '%s\n' "${KO_ARGS[@]}"
    return 0
  fi

  ko "${KO_ARGS[@]}"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
