# Jenkins infrastructure

This repository builds a Jenkins controller and ephemeral Docker agents for
Flutter, Java, and Node.js pipelines.

## Reproducible build contract

Docker Compose **2.24.0 or newer** is required. Builds also require Docker
Engine 24.0+ with BuildKit enabled and a Buildx release compatible with that
engine.

A build is defined entirely by the committed contents of:

- `compose.yaml`, `jenkins/compose.yaml`, and
  `jenkins/agents/compose.agents.yaml`;
- every Dockerfile and `.dockerignore` in `jenkins/`;
- `jenkins/toolchain.lock`;
- `jenkins/plugins/plugins.txt`;
- `jenkins/jcasc/jenkins.yaml`;
- `jenkins/docker-socket-proxy/haproxy.cfg.template`;
- `.env.example` for the names and shape of runtime configuration.

Runtime credentials under `jenkins/secrets/` and values copied into `.env` are
required to start Jenkins, but must never affect image layers. The build must
not read uncommitted files, the host package manager, the host architecture
unless it is an explicit target platform, or the current wall-clock time.

For a given Git commit, target platform, and `SOURCE_DATE_EPOCH`, a build is
reproducible only when two clean builds:

1. use independent BuildKit builders with empty local and registry caches;
2. resolve the same immutable base-image manifests and locked artifacts;
3. export byte-identical OCI manifests, configs, and layers for the controller
   and every agent image;
4. therefore produce the same OCI digest for every image.

A running container that behaves the same but has a different OCI digest does
not satisfy this contract. Any intended dependency update must change a
committed lock input and pass the two-build reproducibility check before it is
merged.
