.PHONY: help install lock sync format format-check lint lint-check \
        hooks hooks-run hooks-update build test \
        compose-base compose-browser compose-down clean

YAMLLINT ?= yamllint
PRECOMMIT ?= pre-commit
RUFF_VERSION ?= 0.15.4

# Either engine works. `make build ENGINE=podman` and `make compose-browser
# ENGINE=podman` are exercised in CI alongside the Docker path.
ENGINE ?= docker
COMPOSE ?= $(ENGINE) compose

VARIANT ?= browser
IMAGE ?= rfc:$(VARIANT)
PLATFORM ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

ENTRYPOINT := src/entrypoint/rf-entrypoint

# Default target: show available commands
help:
	@echo "Available targets:"
	@echo "  make install         - Install the pinned tooling from package-lock.json"
	@echo "  make lock            - Regenerate uv.lock from pyproject.toml"
	@echo "  make sync            - Create a local .venv with the base dependency group"
	@echo "  make format          - Format all files with Prettier and Ruff"
	@echo "  make format-check    - Check formatting without modifying files"
	@echo "  make lint            - Lint YAML, Python, the Dockerfile and the suites"
	@echo "  make lint-check      - Lint everything (for CI)"
	@echo "  make hooks           - Install the git hooks (pre-commit + commit-msg)"
	@echo "  make hooks-run       - Run every pre-commit hook over the whole tree"
	@echo "  make hooks-update    - Bump the pinned hook revisions (Renovate does this too)"
	@echo "  make build           - Build one image  (VARIANT=base|browser|selenium)"
	@echo "  make test            - Run the bundled suites against that image"
	@echo "  make compose-base    - Run the base suite via compose"
	@echo "  make compose-browser - Run the browser suite via compose (starts the site)"
	@echo "  make compose-down    - Tear the compose project down"
	@echo "  make clean           - Remove the local venv, reports and caches"
	@echo ""
	@echo "Set ENGINE=podman to use Podman instead of Docker."

# Install the pinned Prettier version
install:
	npm ci

# Restore dependencies whenever the lockfile is newer than node_modules
node_modules: package-lock.json
	npm ci
	@touch node_modules

# Python dependencies are locked separately, by uv
lock:
	uv lock

sync:
	uv sync --locked --no-default-groups --group base

# Format YAML/Markdown/JSON with Prettier and the entrypoint with Ruff
format: node_modules
	npm run format
	uvx ruff@$(RUFF_VERSION) format $(ENTRYPOINT)

# Verify formatting (useful for CI)
format-check: node_modules
	npm run format:check
	uvx ruff@$(RUFF_VERSION) format --check $(ENTRYPOINT)

# Lint everything this repo actually contains. There are no shell scripts here,
# so Ruff stands where shellcheck would.
lint:
	uv lock --check
	$(YAMLLINT) .
	uvx ruff@$(RUFF_VERSION) check $(ENTRYPOINT)
	uv run --no-default-groups --group base robocop check tests/
	@command -v hadolint >/dev/null 2>&1 \
		&& hadolint Dockerfile \
		|| echo "hadolint not installed; skipping Dockerfile lint"

# Lint everything (useful for CI)
lint-check: lint

# Install the git hooks (pre-commit itself lives outside this repo:
# `uv tool install pre-commit`, brew or pipx)
# commit-msg is a separate hook type; without it commitlint never runs.
hooks:
	$(PRECOMMIT) install --hook-type pre-commit --hook-type commit-msg

# Run every hook over the whole tree, not just the files a commit touches
hooks-run:
	$(PRECOMMIT) run --all-files

# Bump the pinned hook revisions (Renovate does this too)
hooks-update:
	$(PRECOMMIT) autoupdate

# Docker needs buildx for the BuildKit cache mounts; Podman/Buildah support
# them natively, so it takes a plain `podman build`.
build:
ifeq ($(ENGINE),docker)
	docker buildx build --target $(VARIANT) --platform $(PLATFORM) --load -t $(IMAGE) .
else
	$(ENGINE) build --target $(VARIANT) --platform $(PLATFORM) -t $(IMAGE) .
endif

# Deliberately no --shm-size=1g: the image has to work at the default.
# The :z labels are for SELinux hosts under Podman; other platforms ignore them.
test: build
	mkdir -p reports
	$(ENGINE) run --rm \
		-v "$(CURDIR)/tests/base:/opt/robotframework/tests:ro,z" \
		-v "$(CURDIR)/reports:/opt/robotframework/reports:z" \
		$(IMAGE)

# One-shot runs through compose, which also brings up the static site the
# browser suite needs.
compose-base:
	$(COMPOSE) run --rm base

compose-browser:
	$(COMPOSE) run --rm browser

compose-down:
	$(COMPOSE) down --remove-orphans

# reports/.gitkeep is tracked -- keep the directory, drop its contents.
clean:
	-$(COMPOSE) down --remove-orphans 2>/dev/null
	rm -rf .venv node_modules reports-* .ruff_cache .robocop_cache .pabotsuitenames
	-find reports -mindepth 1 ! -name .gitkeep -delete
