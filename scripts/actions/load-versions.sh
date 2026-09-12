#!/usr/bin/env bash
#
# Backs .github/actions/load-versions. Publishes every pinned version from
# .versions.yaml as a step output.

set -euo pipefail

# shellcheck source=scripts/actions/lib.sh
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

KEYS="
tools.ko
tools.crane
tools.syft
tools.cosign
tools.trivy
tools.actionlint
tools.yamllint
tools.shellcheck
images.ko_default_base
"

main() {
  local key name value
  for key in ${KEYS}; do
    name="${key#*.}"
    value="$("${REPO_ROOT}/scripts/versions.sh" "${key}" "${REPO_ROOT}/.versions.yaml")"
    emit_output "${name}" "${value}"
    printf '%-16s %s\n' "${name}" "${value}"
  done
}

main "$@"
