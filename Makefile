.PHONY: help lock sync lint format build test clean

VARIANT ?= browser
IMAGE   ?= rfc:$(VARIANT)
PLATFORM ?= linux/$(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

help:
	@echo "Targets:"
	@echo "  make lock              - Regenerate uv.lock from pyproject.toml"
	@echo "  make sync              - Create a local .venv with the base group"
	@echo "  make lint              - Lint the entrypoint, Dockerfile and suites"
	@echo "  make format            - Format the entrypoint"
	@echo "  make build             - Build one variant   (VARIANT=base|browser|selenium)"
	@echo "  make test              - Run the bundled suites against that image"
	@echo "  make clean             - Remove local venv and reports"

lock:
	uv lock

sync:
	uv sync --locked --no-default-groups --group base

lint:
	uv lock --check
	uvx ruff@0.15.4 check src/entrypoint/rf-entrypoint
	uv run --no-default-groups --group base robocop check tests/
	@command -v hadolint >/dev/null 2>&1 \
		&& hadolint Dockerfile \
		|| echo "hadolint not installed; skipping Dockerfile lint"

format:
	uvx ruff@0.15.4 format src/entrypoint/rf-entrypoint

build:
	docker buildx build --target $(VARIANT) --platform $(PLATFORM) --load -t $(IMAGE) .

# Deliberately no --shm-size=1g: the image has to work at the default.
test: build
	mkdir -p reports
	docker run --rm \
		-v "$(CURDIR)/tests/base:/opt/robotframework/tests:ro" \
		-v "$(CURDIR)/reports:/opt/robotframework/reports" \
		$(IMAGE)

clean:
	rm -rf .venv reports .ruff_cache
