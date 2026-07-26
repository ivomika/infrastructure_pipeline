# Controlled dependency updates

Renovate proposes updates to the pinned controller, inbound agent, socket
proxy, Node.js, Maven, Flutter, Jenkins plugins, and GitHub Actions. It never
merges a proposal automatically.

`renovate.json` updates only the primary version or image tag/digest.
`scripts/refresh-locks.sh` then derives all versioned artifact URLs, obtains
official checksums, resolves the complete Jenkins plugin graph, records every
plugin SHA-256, and refreshes registry digests. The resulting files are part of
the same pull request:

- `jenkins/toolchain.lock`;
- `jenkins/plugins/plugins.txt`;
- `jenkins/plugins/plugins.lock.txt`;
- `jenkins/plugins/plugins.sha256`.

Android command-line tools and Debian snapshot changes remain deliberate manual
updates because their compatible package sets must be selected together. Edit
their primary values in `toolchain.lock`, run `scripts/refresh-locks.sh`, and
open the same reviewed pull request.

## Bot setup

Run a trusted self-hosted Renovate instance. Repository post-upgrade commands
are disabled by default, so its administrator must allow only this exact
command:

```text
^scripts/refresh-locks\.sh$
```

Do not enable a general shell executor. The bot runs weekly, waits seven days
after a release, requires Dependency Dashboard approval, limits concurrent
proposals, and leaves `automerge` disabled.

## Required pull-request checks

Protect the production branch and require a human approval plus these checks:

- `Dependency update gates / validate-locks`;
- `Dependency update gates / security-and-smoke`;
- `Reproducible images / compare-clean-builds`.

The first gate verifies live registry digests and official artifact/plugin
checksums. The second builds the images, blocks critical unfixed
vulnerabilities, starts an isolated Compose project, and provisions Node.js,
Java, and Flutter agents. The reproducibility workflow performs two clean
BuildKit builds and compares OCI metadata.

The security/smoke and reproducibility jobs need a trusted Linux x86-64 runner
labelled `jenkins-infra`, with Docker, Compose 2.24+, Buildx, at least 8 GiB of
memory, and at least 80 GiB of free Docker storage. No deployment step exists in
either workflow: production images change only after review and merge of the
explicit lock-file diff.

For a manual proposal, update primary versions, then run:

```bash
scripts/refresh-locks.sh
scripts/verify-locks.sh
```

Use `scripts/refresh-locks.sh --check` to prove that derived lock data is
current without modifying tracked files.
