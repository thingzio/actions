#!/usr/bin/env bash
#
# Fail-closed checks that run after a build and before anything is signed.
#
#   scripts/validate-digests.sh digests <expect-index> <index> <platform>...
#   scripts/validate-digests.sh sbom    <file>
#
# These exist because the failure modes they catch are all silent. A release
# that lost an architecture, an SBOM attached to the wrong subject, or a
# document that is not actually CycloneDX all produce a green build and a
# referrers listing that reads as correct. The cost of checking is a second; the
# cost of not checking is a signed claim that is wrong.
#
# digests:
#   expect-index is "true" when more than one platform was requested. In that
#   case the build must have produced a real multi-platform index: every child
#   manifest digest must differ from the index digest (equality means crane
#   returned the reference's own digest, so the image is not an index) and the
#   child digests must all differ from each other (equality means two platforms
#   resolved to the same manifest, so an architecture went missing).
#
#   With a single platform the build legitimately produces a plain manifest, so
#   both checks are skipped and the SBOM and the provenance share one subject.
#   This is the only case in which they do.
#
# sbom:
#   `cosign attest --type cyclonedx` stamps the predicate type
#   https://cyclonedx.org/bom on whatever bytes it is handed. A JSON document in
#   the wrong format would be published under a CycloneDX predicate type and
#   nothing downstream would notice, so the format is asserted here instead.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

DIGEST_PATTERN='^sha256:[a-f0-9]{64}$'

usage() {
  printf 'usage: %s digests <true|false> <index-digest> <platform-digest>...\n' "${0##*/}" >&2
  printf '       %s sbom <file>\n' "${0##*/}" >&2
  exit 2
}

require_digest() {
  local name="$1" value="$2"
  require_no_newline "${name}" "${value}"
  [[ "${value}" =~ ${DIGEST_PATTERN} ]] ||
    die "${name} must be of the form sha256:<64 lowercase hex>, got '${value}'"
}

validate_digests() {
  local expect_index="$1" index="$2"
  shift 2

  case "${expect_index}" in
    true | false) ;;
    *) die "expect-index must be 'true' or 'false', got '${expect_index}'" ;;
  esac

  require_digest "index digest" "${index}"
  [ "$#" -gt 0 ] || die "at least one platform digest is required"

  local digests i j count
  digests=("$@")
  count="${#digests[@]}"

  i=0
  while [ "${i}" -lt "${count}" ]; do
    require_digest "platform digest $((i + 1))" "${digests[${i}]}"
    i=$((i + 1))
  done

  if [ "${expect_index}" = "false" ]; then
    [ "${count}" = "1" ] ||
      die "expect-index is false but ${count} platform digests were given; a single-platform build has exactly one"
    [ "${digests[0]}" = "${index}" ] ||
      die "expect-index is false so the single platform digest must equal the index digest, got '${digests[0]}' and '${index}'"
    return 0
  fi

  [ "${count}" -ge 2 ] ||
    die "expect-index is true but only ${count} platform digest was given"

  i=0
  while [ "${i}" -lt "${count}" ]; do
    [ "${digests[${i}]}" != "${index}" ] ||
      die "platform digest ${digests[${i}]} equals the index digest; the image is not a multi-platform index"
    i=$((i + 1))
  done

  # O(n^2) over at most a handful of platforms, and clearer than sorting.
  i=0
  while [ "${i}" -lt "${count}" ]; do
    j=$((i + 1))
    while [ "${j}" -lt "${count}" ]; do
      [ "${digests[${i}]}" != "${digests[${j}]}" ] ||
        die "platform digests $((i + 1)) and $((j + 1)) are identical (${digests[${i}]}); the image lost an architecture"
      j=$((j + 1))
    done
    i=$((i + 1))
  done
}

validate_sbom() {
  local file="$1" bom_format spec_version

  require_set "sbom file" "${file}"
  [ -f "${file}" ] || die "SBOM file not found: ${file}"
  [ -s "${file}" ] || die "SBOM file is empty: ${file}"

  command -v jq >/dev/null 2>&1 || die "jq is required to validate an SBOM but is not installed"

  jq -e . "${file}" >/dev/null 2>&1 || die "SBOM file is not valid JSON: ${file}"

  bom_format="$(jq -r '.bomFormat // ""' "${file}")"
  [ "${bom_format}" = "CycloneDX" ] ||
    die "${file} has bomFormat '${bom_format:-<absent>}', want CycloneDX"

  spec_version="$(jq -r '.specVersion // ""' "${file}")"
  [ -n "${spec_version}" ] || die "${file} has no specVersion"

  # A CycloneDX document with no components almost always means the scan
  # silently targeted the wrong reference; a real image has at least its own
  # base layer contents.
  local components
  components="$(jq -r '(.components // []) | length' "${file}")"
  [ "${components}" -gt 0 ] ||
    die "${file} lists no components; the scan probably targeted the wrong reference"

  log "SBOM ${file}: CycloneDX ${spec_version}, ${components} components"
}

main() {
  local command="${1-}"
  [ -n "${command}" ] || usage
  shift

  case "${command}" in
    digests)
      [ "$#" -ge 3 ] || usage
      validate_digests "$@"
      ;;
    sbom)
      [ "$#" = "1" ] || usage
      validate_sbom "$1"
      ;;
    *) usage ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
