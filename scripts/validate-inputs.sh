#!/usr/bin/env bash
#
# Validates and normalizes the caller-supplied inputs of the reusable workflows.
#
#   scripts/validate-inputs.sh image     <registry> <image>
#   scripts/validate-inputs.sh platforms <comma-separated-platforms>
#   scripts/validate-inputs.sh kv        <input-name> <key=value lines>
#   scripts/validate-inputs.sh ko-flags  <flags>
#
# This is the trust boundary. Everything a consumer repository passes into a
# reusable workflow arrives here first, and nothing downstream re-checks it.
#
# Two rules shape the whole file:
#
#   * Nothing validated here may reach a shell as code. Values are passed to
#     later steps through `env:` and quoted expansions, never interpolated into
#     a `run:` block, so the job here is to reject values that would break out
#     of a quoted context or forge a workflow output -- newlines above all.
#
#   * The platform list maps to runner labels. A caller who could name an
#     arbitrary runner could point the build at a compromised self-hosted
#     machine, which would defeat the isolation that the SLSA Build Level 3
#     claim rests on. The mapping is therefore a closed allowlist, not a
#     transformation.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# The OCI repository grammar: lowercase alphanumeric components separated by
# ".", "_", "__" or runs of "-", joined into a path by "/".
OCI_COMPONENT='[a-z0-9]+((\.|_|__|-+)[a-z0-9]+)*'
OCI_REPOSITORY="^${OCI_COMPONENT}(/${OCI_COMPONENT})*\$"

# A registry is a DNS-ish host with an optional port.
REGISTRY_PATTERN='^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$'

usage() {
  printf 'usage: %s <image|platforms|kv|ko-flags> [args...]\n' "${0##*/}" >&2
  exit 2
}

# validate_image prints "<registry>/<repository>".
#
# `image` is documented as a repository path without a registry host, but
# writing the full reference is the natural mistake, so a leading host is
# accepted when it matches the registry input. It is never silently rewritten:
# a mismatch means the caller believes it is publishing somewhere other than
# where the workflow would publish, and that must fail rather than surprise.
validate_image() {
  local registry="$1" image="$2" first lowered

  require_set registry "${registry}"
  require_set image "${image}"
  require_no_newline registry "${registry}"
  require_no_newline image "${image}"

  [[ "${registry}" =~ ${REGISTRY_PATTERN} ]] ||
    die "registry '${registry}' is not a valid host[:port]"

  case "${image}" in
    *@*) die "image must not contain a digest; pass the repository path only, got '${image}'" ;;
  esac

  # Strip a leading registry host if the caller supplied one. A first path
  # component counts as a host only when it both contains a "." or ":" and is
  # itself a well-formed host: "ghcr.io" and "localhost:5000" qualify,
  # "thingzio" does not, and neither does ".." -- which would otherwise be
  # mistaken for a host and rejected with a confusing message instead of being
  # caught by the repository grammar below.
  first="${image%%/*}"
  if [ "${first}" != "${image}" ]; then
    case "${first}" in
      *.* | *:*)
        if [[ "${first}" =~ ${REGISTRY_PATTERN} ]]; then
          [ "${first}" = "${registry}" ] ||
            die "image names registry '${first}' but the registry input is '${registry}'; remove the host from image or set registry to match"
          image="${image#*/}"
        fi
        ;;
    esac
  fi

  case "${image}" in
    *:*) die "image must not contain a tag; tags come from the tags input, got '${image}'" ;;
  esac

  # Registries reject uppercase repository paths, and github.repository carries
  # the organization's real casing, so an org named "Thingzio" would otherwise
  # fail at push time with an opaque error. Lowercase it and say so.
  lowered="$(printf '%s' "${image}" | tr '[:upper:]' '[:lower:]')"
  if [ "${lowered}" != "${image}" ]; then
    notice "image '${image}' lowercased to '${lowered}'; registries do not accept uppercase repository paths"
    image="${lowered}"
  fi

  [[ "${image}" =~ ${OCI_REPOSITORY} ]] ||
    die "image '${image}' is not a valid OCI repository path"

  printf '%s/%s\n' "${registry}" "${image}"
}

# platform_runner maps a platform to its native GitHub-hosted runner label.
# Adding an entry here is a deliberate act; there is no fallback.
platform_runner() {
  case "$1" in
    linux/amd64) printf 'ubuntu-24.04\n' ;;
    linux/arm64) printf 'ubuntu-24.04-arm\n' ;;
    *) die "unsupported platform '$1'; supported platforms are linux/amd64 and linux/arm64" ;;
  esac
}

# validate_platforms prints a JSON array of {platform, arch, runner} objects,
# suitable for a matrix `strategy`. Hand-built rather than piped through jq
# because every value comes from the closed allowlist above and so needs no
# escaping, and because this must run before any tool is installed.
validate_platforms() {
  local input="$1" normalized entry arch runner json="" saved_ifs

  require_set platforms "${input}"
  require_no_newline platforms "${input}"

  normalized="$(printf '%s\n' "${input}" | tr ',' '\n' |
    awk '{ gsub(/[[:space:]]/, ""); if ($0 != "" && !seen[$0]++) print }')"
  [ -n "${normalized}" ] || die "the platforms input contained no usable platform"

  saved_ifs="${IFS}"
  IFS='
'
  set -f
  for entry in ${normalized}; do
    runner="$(platform_runner "${entry}")"
    arch="${entry#*/}"
    json="${json}{\"platform\":\"${entry}\",\"arch\":\"${arch}\",\"runner\":\"${runner}\"},"
  done
  set +f
  IFS="${saved_ifs}"

  printf '[%s]\n' "${json%,}"
}

# validate_kv normalizes a newline-separated key=value list, used for OCI labels
# and Docker build arguments. Splitting on newlines only is deliberate: a label
# value legitimately contains commas.
validate_kv() {
  local name="$1" input="$2" line key saved_ifs

  [ -n "${input}" ] && [ -n "$(printf '%s' "${input}" | tr -d '[:space:]')" ] || return 0

  saved_ifs="${IFS}"
  IFS='
'
  set -f
  for line in ${input}; do
    line="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "${line}" ] || continue

    case "${line}" in
      *=*) ;;
      *) die "${name} entry '${line}' is not in key=value form" ;;
    esac

    key="${line%%=*}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] ||
      die "${name} key '${key}' must start with a letter or underscore and contain only A-Za-z0-9_.-"

    printf '%s\n' "${line}"
  done
  set +f
  IFS="${saved_ifs}"
}

# validate_ko_flags enforces a closed allowlist of ko flags.
#
# ko_flags exists because a handful of ko knobs are genuinely useful and not
# worth a dedicated input each. It is not an escape hatch: an open flag list
# would let a caller change the platform set (bypassing the runner allowlist)
# or redirect the push, so anything not named here is refused.
validate_ko_flags() {
  local input="$1" flag saved_ifs

  [ -n "${input}" ] && [ -n "$(printf '%s' "${input}" | tr -d '[:space:]')" ] || return 0

  saved_ifs="${IFS}"
  IFS=$' \t\n'
  set -f
  for flag in ${input}; do
    [ -n "${flag}" ] || continue
    case "${flag}" in
      --image-user=[0-9]*)
        case "${flag#--image-user=}" in
          *[!0-9]* | "") die "ko flag '${flag}' must set a numeric UID" ;;
        esac
        ;;
      --image-annotation=*=*) ;;
      --disable-optimizations) ;;
      --debug) ;;
      *)
        die "ko flag '${flag}' is not allowed; permitted flags are --image-user=<uid>, --image-annotation=<k>=<v>, --disable-optimizations, --debug"
        ;;
    esac
    printf '%s\n' "${flag}"
  done
  set +f
  IFS="${saved_ifs}"
}

main() {
  local command="${1-}"
  [ -n "${command}" ] || usage
  shift

  case "${command}" in
    image)
      [ "$#" = "2" ] || usage
      validate_image "$1" "$2"
      ;;
    platforms)
      [ "$#" = "1" ] || usage
      validate_platforms "$1"
      ;;
    kv)
      [ "$#" = "2" ] || usage
      validate_kv "$1" "$2"
      ;;
    ko-flags)
      [ "$#" = "1" ] || usage
      validate_ko_flags "$1"
      ;;
    *) usage ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
