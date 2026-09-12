#!/usr/bin/env bash
#
# Checks a caller's .goreleaser.yaml against the obligations release-go.yaml
# depends on, before goreleaser is allowed to run.
#
#   scripts/check-goreleaser-config.sh <directory>
#
# release-go.yaml makes three promises that a caller's configuration can quietly
# break, and each one breaks silently -- CI stays green and the operator learns
# later, from a consumer:
#
#   * release.draft: true. The build job creates the GitHub release BEFORE the
#     attest job signs anything. Without draft, a live, publicly downloadable
#     release exists for the length of the attest job with no signature and no
#     provenance. goreleaser's own default is draft: false, so a caller who does
#     nothing gets the unsafe shape.
#
#   * release.use_existing_draft: true. GitHub's get-release-by-tag lookup does
#     not return drafts, so on a re-run after a partial failure goreleaser
#     cannot see the draft it made last time and creates a second one for the
#     same tag. The attest and publish jobs then address "the" release by tag
#     with two candidates present.
#
#   * No signs: block. Signing happens in the attest job, where the caller
#     cannot reach the identity. release-go.yaml passes --skip=sign, so a signs
#     block is ignored rather than honoured: a signature the caller believes
#     they have and do not.
#
# Deliberately awk rather than yq, matching scripts/versions.sh: this runs
# before any tool is installed, and a reader that needs an installed binary
# would be circular. The supported subset is block-style YAML with scalar
# values, which is what every goreleaser configuration in practice is. Anything
# this cannot parse reads as absent and therefore fails closed -- and the build
# job re-asserts the draft state against the GitHub API afterwards, so a
# configuration shape this misreads is caught there rather than shipped.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# The names goreleaser searches, in its own order of preference.
CONFIG_NAMES='.goreleaser.yaml .goreleaser.yml goreleaser.yaml goreleaser.yml'

usage() {
  printf 'usage: %s <directory>\n' "${0##*/}" >&2
  exit 2
}

# find_config echoes the path of the goreleaser configuration in a directory.
find_config() {
  local dir="$1" name
  for name in ${CONFIG_NAMES}; do
    if [ -r "${dir}/${name}" ]; then
      printf '%s\n' "${dir}/${name}"
      return 0
    fi
  done
  return 1
}

# has_top_level_key succeeds when the document has the given key at column zero.
has_top_level_key() {
  local file="$1" want="$2"
  awk -v want="${want}" '
    { line = $0; sub(/[[:space:]]*#.*$/, "", line) }
    line ~ /^[A-Za-z_][A-Za-z0-9_-]*:/ {
      head = line
      sub(/:.*$/, "", head)
      if (head == want) { found = 1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "${file}"
}

# block_value echoes the scalar value of a direct child of a top-level block,
# or nothing when the block, the key, or a parseable value is absent.
#
# Only direct children count: the indent of the block's first child fixes the
# depth, so a same-named key nested deeper inside the block cannot answer for
# it.
block_value() {
  local file="$1" block="$2" key="$3"
  awk -v want_block="${block}" -v want_key="${key}" '
    { line = $0; sub(/[[:space:]]*#.*$/, "", line) }
    line ~ /^[[:space:]]*$/ { next }
    line ~ /^[A-Za-z_][A-Za-z0-9_-]*:/ {
      head = line
      sub(/:.*$/, "", head)
      in_block = (head == want_block)
      depth = -1
      next
    }
    !in_block { next }
    {
      indent = match(line, /[^[:space:]]/) - 1
      if (depth < 0) depth = indent
      if (indent != depth) next
    }
    line ~ /^[[:space:]]+[A-Za-z_][A-Za-z0-9_-]*:/ {
      k = line
      sub(/^[[:space:]]+/, "", k)
      sub(/:.*$/, "", k)
      if (k != want_key) next
      v = line
      sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      gsub(/^["\047]|["\047]$/, "", v)
      print v
      exit
    }
  ' "${file}"
}

main() {
  local dir="${1-}" config failed=0
  [ -n "${dir}" ] || usage
  [ -d "${dir}" ] || die "cannot read directory '${dir}'"

  if ! config="$(find_config "${dir}")"; then
    printf '::error::no goreleaser configuration in %s (looked for: %s)\n' \
      "${dir}" "${CONFIG_NAMES}" >&2
    exit 1
  fi
  printf 'checking %s\n' "${config}"

  if [ "$(block_value "${config}" release disable)" = "true" ]; then
    printf '::error::release.disable is set, but release-go.yaml exists to publish a GitHub release\n' >&2
    failed=1
  fi

  if [ "$(block_value "${config}" release draft)" != "true" ]; then
    printf '::error::release.draft must be true. The release is created before it is signed; without draft it is publicly downloadable, unsigned, for the length of the attest job\n' >&2
    failed=1
  fi

  if [ "$(block_value "${config}" release use_existing_draft)" != "true" ]; then
    printf '::error::release.use_existing_draft must be true. GitHub does not return drafts by tag, so a re-run creates a second draft for the same tag and the attest job can no longer tell which release it is signing\n' >&2
    failed=1
  fi

  if has_top_level_key "${config}" signs; then
    printf '::error::remove the signs block. Signing happens in the attest job, where the caller cannot reach the identity; release-go.yaml passes --skip=sign, so this block is a signature you believe you have and do not\n' >&2
    failed=1
  fi

  # Not fatal: a caller may legitimately not want SBOMs. Silence would be
  # worse than a nudge, because the workflow installs syft either way and the
  # documentation advertises the capability.
  if ! has_top_level_key "${config}" sboms; then
    printf '::warning::no sboms block, so this release will carry no SBOM. release-go.yaml installs syft for this; see docs/release-go.md\n' >&2
  fi

  [ "${failed}" = "0" ] || exit 1
  printf 'goreleaser configuration satisfies release-go.yaml\n'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
