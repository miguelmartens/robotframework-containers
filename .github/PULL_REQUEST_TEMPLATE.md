## What and why

<!-- What changes, and what problem it solves. Link the issue if there is one. -->

## How it was verified

<!--
Which engine and architecture you ran on, and what you actually ran.
If you measured something — image size, build time — put the numbers here.
Size changes in particular are worth stating explicitly.
-->

## Checklist

- [ ] `make lint` and `make format-check` pass
- [ ] `make build` and `make test` pass for the affected variant(s)
- [ ] Touched the `Dockerfile`? Checked `make build ENGINE=podman` too
- [ ] Changed a dependency? Ran `make lock` and committed `uv.lock`
- [ ] New behaviour has a test in `tests/` or a regression step in the workflow
- [ ] Image size did not grow meaningfully, or the reason is in "What and why"

<!--
If you are changing one of the design decisions in CONTRIBUTING.md -- the
gid-0 contract, arbitrary-UID support, shlex option parsing, the ENTRYPOINT,
or working at the default /dev/shm -- please say so explicitly. Each of those
exists because of a specific bug, and they are easy to undo by accident.
-->
