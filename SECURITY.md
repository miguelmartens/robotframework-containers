# Security policy

## Reporting a vulnerability

Report privately through GitHub:
**[Report a vulnerability](https://github.com/miguelmartens/robotframework-containers/security/advisories/new)**.

Please do not open a public issue for something exploitable.

Useful things to include: the image tag or digest, the architecture, the engine
and version (`docker version` / `podman version`), and the smallest thing that
reproduces it.

### What to expect

This project is currently maintained by one person. I will acknowledge a report
within roughly a week and tell you honestly whether and when I can act on it.

I would rather state that plainly than publish a 24-hour SLA I cannot keep. The
project this one replaces died of a maintainer shortfall that was never
acknowledged, and pretending otherwise helps nobody. If a report is urgent and I
have gone quiet, escalate by opening a public issue saying only that you are
waiting on a private report — no details.

## What is in scope

- The `Dockerfile`, the entrypoint, and the CI workflows in this repository.
- The way the images are built, configured and published: user and permission
  handling, the published tags, the signatures and attestations.
- Vulnerable versions of bundled dependencies that a rebuild would fix.

## What is not

- Vulnerabilities in Robot Framework, Playwright, Selenium, Debian or any other
  upstream project. Report those to the project concerned; if a fixed version
  exists, a bump here is a normal pull request, not a security report.
- Findings from a scanner with no reachable exploit path and no available fix.
  The CI gate already runs with `--ignore-unfixed` for that reason.
- Anything that requires the attacker to already control the test suites you
  mount. The image runs whatever `robot` code you give it; that is its job.

## How this project tries to stay boring

|             |                                                                                                                                                                                    |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base image  | Pinned by digest. Renovate moves the digest; the SBOM records what shipped                                                                                                         |
| OS packages | `apt-get upgrade` at build so fixes land without waiting for a base-image republish                                                                                                |
| Python      | One hash-pinned `uv.lock`, one virtualenv per variant, no compilers in a runtime image                                                                                             |
| Scanning    | Trivy gates every build on fixable `CRITICAL`/`HIGH`. It fails the build; it does not file a report and continue                                                                   |
| Rebuilds    | A scheduled monthly build re-runs the CVE gate against current sources, so drift surfaces as a failed run rather than silently                                                     |
| Provenance  | SBOM and `mode=max` provenance attestations, plus keyless cosign signatures                                                                                                        |
| Tags        | A full version is never re-pushed. Upstream republished `4.0.0` with different contents and broke people ([#423](https://github.com/ppodgorsek/docker-robot-framework/issues/423)) |

Deliberate choices that a scanner or linter may flag, with the reasoning written
down rather than silently suppressed:

- **No pinned `apt-get install` versions** (hadolint DL3008). The archive keeps
  only the current version of a package per suite, so a pin disappears at the
  next point release and the build breaks. See `.hadolint.yaml`.
- **`uv` instead of `pip`** in the runtime images. pip vendors its own copies of
  `msgpack` and `setuptools`, both with published advisories, for code paths
  only pip uses.

## Running the images safely

The images run as uid `1000`, gid `0`, with a read-only root filesystem and no
capabilities:

```bash
docker run --rm --read-only --tmpfs /tmp \
  --cap-drop=ALL --security-opt=no-new-privileges \
  -v "$PWD/tests:/opt/robotframework/tests:ro" \
  -v "$PWD/reports:/opt/robotframework/reports" \
  ghcr.io/miguelmartens/robotframework-containers:browser
```

That configuration is a CI regression test, not a suggestion.

### Verifying what you pulled

```bash
IMAGE=ghcr.io/miguelmartens/robotframework-containers:browser

cosign verify "$IMAGE" \
  --certificate-identity-regexp='^https://github.com/miguelmartens/robotframework-containers/' \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

docker buildx imagetools inspect "$IMAGE" --format '{{ json .SBOM }}'
```

Pin by digest in CI. The moving tags are a convenience for humans.
