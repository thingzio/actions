#!/usr/bin/env bash
#
# Reads one scalar value out of .versions.yaml.
#
#   scripts/versions.sh tools.ko          -> v0.19.1
#   scripts/versions.sh images.ko_default_base
#
# Deliberately implemented in awk rather than with yq. The Makefile needs a tool
# version before it can install any tool, so a reader that depends on an
# installed binary would be circular. The supported subset is exactly the shape
# .versions.yaml uses: two levels, scalar values, "#" comments. Values may
# contain ":" but may not contain "#".
#
# Exits non-zero with a message on stderr when the key is absent, so callers can
# rely on `set -e` rather than checking for an empty string.

set -euo pipefail

usage() {
  printf 'usage: %s <section>.<key> [versions-file]\n' "${0##*/}" >&2
  exit 2
}

main() {
  local key="${1-}" file="${2-}" section name value
  [ -n "${key}" ] || usage

  if [ -z "${file}" ]; then
    file="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/.versions.yaml"
  fi
  [ -r "${file}" ] || { printf '%s: cannot read %s\n' "${0##*/}" "${file}" >&2; exit 1; }

  case "${key}" in
    *.*) ;;
    *) printf '%s: key must be <section>.<name>, got %s\n' "${0##*/}" "${key}" >&2; exit 2 ;;
  esac
  section="${key%%.*}"
  name="${key#*.}"

  value="$(
    awk -v want_section="${section}" -v want_key="${name}" '
      { sub(/[[:space:]]*#.*$/, "") }
      /^[[:space:]]*$/ { next }
      /^[^[:space:]]/ {
        head = $0
        sub(/:.*$/, "", head)
        in_section = (head == want_section)
        next
      }
      in_section {
        k = $0
        sub(/^[[:space:]]+/, "", k)
        sub(/:.*$/, "", k)
        if (k == want_key) {
          v = $0
          sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", v)
          sub(/[[:space:]]+$/, "", v)
          gsub(/^["\047]|["\047]$/, "", v)
          print v
          exit
        }
      }
    ' "${file}"
  )"

  if [ -z "${value}" ]; then
    printf '%s: %s not found in %s\n' "${0##*/}" "${key}" "${file}" >&2
    exit 1
  fi
  printf '%s\n' "${value}"
}

main "$@"
