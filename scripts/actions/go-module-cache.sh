#!/usr/bin/env bash
#
# Decides whether the Go module cache can be used, and where its lock file is.
#
#   CHECKOUT_DIR      directory the caller's repository was checked out into
#   WORKING_DIRECTORY caller-supplied module directory, relative to the checkout
#
# Emits to GITHUB_OUTPUT:
#
#   cache  "true" when a go.sum exists and the cache should be enabled
#   dir    normalized module directory, e.g. "src" or "src/api"
#   path   normalized go.sum path, suitable for cache-dependency-path
#
# This lives in a script rather than inline in the workflow for the same reason
# ko-build.sh does: inline YAML is linted by nothing and testable by nothing,
# and the path arithmetic here has a sharp edge that nothing caught.
#
# The sharp edge:
#
#   working_directory defaults to "." and the path was composed as
#   "src/${WORKING_DIRECTORY}/go.sum", yielding "src/./go.sum". The shell `-f`
#   test accepts that, so the step reported cache=true, and then
#   actions/cache rejected the pattern at restore time with
#
#     Invalid pattern 'src/./go.sum'. Relative pathing '.' and '..' is not allowed.
#
#   The build still succeeded, so nothing failed and nothing was obviously
#   wrong -- the module cache simply never restored, for every caller using the
#   default working directory, which is all of them. A slow build is a much
#   quieter bug than a broken one.
#
# Normalizing once here, and emitting the directory as well as the file, means
# the workflow composes no paths of its own.

set -euo pipefail

# shellcheck source=scripts/lib/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

: "${CHECKOUT_DIR:=src}"
: "${WORKING_DIRECTORY:=.}"

# Collapse the "current directory" spellings to nothing, and strip a leading
# "./" from anything else, so "." "./" "" all mean the root and "./api" and
# "api" mean the same subdirectory. Applied to both halves of the join, because
# a caller that checks its source out at the workspace root passes
# CHECKOUT_DIR=".", and "." on the left of the join is the same bug as "." on
# the right.
normalize_dir() {
  local dir="$1"
  case "${dir}" in
    '' | '.' | './') printf '' ;;
    *)
      dir="${dir#./}"
      # A trailing slash would produce "src/api//go.sum".
      printf '%s' "${dir%/}"
      ;;
  esac
}

# join_path composes the non-empty segments, so no "." or "//" can survive.
join_path() {
  local head="$1" tail="$2"
  if [ -z "${head}" ]; then
    printf '%s' "${tail}"
  elif [ -z "${tail}" ]; then
    printf '%s' "${head}"
  else
    printf '%s/%s' "${head}" "${tail}"
  fi
}

main() {
  local checkout workdir prefix dir lock

  checkout="$(normalize_dir "${CHECKOUT_DIR}")"
  workdir="$(normalize_dir "${WORKING_DIRECTORY}")"
  prefix="$(join_path "${checkout}" "${workdir}")"

  # Two spellings of the same location, because they are consumed by things
  # with incompatible rules. `dir` feeds `working-directory:`, which requires a
  # non-empty value, so the root is ".". `path` feeds cache-dependency-path,
  # which is a glob pattern that rejects a "." segment outright, so the root is
  # bare. Conflating them is what broke the cache in the first place.
  dir="${prefix:-.}"
  lock="$(join_path "${prefix}" go.sum)"

  emit_output dir "${dir}"

  if [ -f "${lock}" ]; then
    emit_output cache true
    emit_output path "${lock}"
  else
    emit_output cache false
    emit_output path ''
    notice "no go.sum found in ${dir}; building without the module cache"
  fi
}

main "$@"
