# Entry point for local development. Every target here is the same command the
# `ci` workflow runs, reading the same pinned versions from .versions.yaml, so a
# green `make verify` on a laptop means a green CI run.
#
# Tools are installed into ./.bin (gitignored) rather than system-wide, so this
# repository can never be linted by whatever version happens to be on $PATH.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

BIN := $(CURDIR)/.bin
VERSIONS := $(CURDIR)/scripts/versions.sh
export PATH := $(BIN):$(PATH)

ACTIONLINT_VERSION := $(shell $(VERSIONS) tools.actionlint)
YAMLLINT_VERSION := $(shell $(VERSIONS) tools.yamllint)
SHELLCHECK_VERSION := $(shell $(VERSIONS) tools.shellcheck)
ZIZMOR_VERSION := $(shell $(VERSIONS) tools.zizmor)

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*## " } \
		/^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } \
		/^## / { printf "\n%s\n", substr($$0, 4) }' $(MAKEFILE_LIST)
	@printf '\n'

## Verification

.PHONY: verify
verify: lint test ## Run every check CI runs

.PHONY: test
test: ## Run the shell test suite
	@./test/run.sh

.PHONY: test-offline
test-offline: ## Run the shell test suite, skipping tests that need the network
	@THINGZ_SKIP_NETWORK_TESTS=1 ./test/run.sh

.PHONY: lint
lint: lint-actions lint-yaml lint-shell lint-zizmor ## Run every linter

.PHONY: lint-actions
lint-actions: $(BIN)/actionlint ## Lint workflows and composite actions
	@actionlint -color

.PHONY: lint-yaml
lint-yaml: $(BIN)/yamllint ## Lint YAML formatting
	@yamllint --strict .

.PHONY: lint-shell
lint-shell: $(BIN)/shellcheck ## Lint shell scripts
	@find scripts test -name '*.sh' -type f -print0 \
		| sort -z \
		| xargs -0 $(BIN)/shellcheck --severity=style --external-sources

# The same audit the `ci` workflow reports to code scanning. Without this target
# zizmor findings could only ever be discovered after a push, which is how 40 of
# them accumulated unnoticed. Online audits are off: they need a GitHub token,
# and a check that fails on a laptop for lack of credentials is not a check.
.PHONY: lint-zizmor
lint-zizmor: $(BIN)/zizmor ## Audit workflows for Actions-specific security issues
	@$(BIN)/zizmor --no-online-audits --quiet .github/

## Tooling

.PHONY: tools
tools: $(BIN)/actionlint $(BIN)/yamllint $(BIN)/shellcheck $(BIN)/zizmor ## Install every pinned tool into ./.bin

$(BIN)/actionlint:
	@./scripts/install-tool.sh actionlint $(ACTIONLINT_VERSION) $(BIN)

$(BIN)/shellcheck:
	@./scripts/install-tool.sh shellcheck $(SHELLCHECK_VERSION) $(BIN)

# yamllint is a Python package, so it gets a dedicated virtualenv rather than a
# `pip install --user` that would depend on the developer's global environment.
$(BIN)/yamllint:
	@python3 -m venv $(BIN)/venv
	@$(BIN)/venv/bin/pip install --quiet --disable-pip-version-check \
		yamllint==$(YAMLLINT_VERSION)
	@ln -sf $(BIN)/venv/bin/yamllint $(BIN)/yamllint

# zizmor publishes a wheel with the binary bundled, so it shares the venv above
# rather than needing a second toolchain. CI runs it as a pinned container image
# through zizmor-action; both resolve the same version from .versions.yaml.
$(BIN)/zizmor:
	@python3 -m venv $(BIN)/venv
	@$(BIN)/venv/bin/pip install --quiet --disable-pip-version-check \
		zizmor==$(ZIZMOR_VERSION)
	@ln -sf $(BIN)/venv/bin/zizmor $(BIN)/zizmor

.PHONY: versions
versions: ## Print every pinned version
	@printf '%-12s %s\n' \
		ko         "$$($(VERSIONS) tools.ko)" \
		crane      "$$($(VERSIONS) tools.crane)" \
		syft       "$$($(VERSIONS) tools.syft)" \
		cosign     "$$($(VERSIONS) tools.cosign)" \
		actionlint "$$($(VERSIONS) tools.actionlint)" \
		yamllint   "$$($(VERSIONS) tools.yamllint)" \
		shellcheck "$$($(VERSIONS) tools.shellcheck)" \
		zizmor     "$$($(VERSIONS) tools.zizmor)"

.PHONY: clean
clean: ## Remove installed tools
	@rm -rf $(BIN)
