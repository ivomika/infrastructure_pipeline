# Jenkins Docker agents

`compose.agents.yaml` is included by the root `compose.yaml`. It declares a
build-only service for the local Flutter agent image. Jenkins Docker Plugin
creates and removes the actual agent containers on demand.

Agent and SDK versions are pinned in `agents.env`.

Build the agent and controller images:

```powershell
docker compose --profile agent-image build
```

Start Jenkins:

```powershell
docker compose up -d jenkins
```

Pipelines request the ephemeral agent by label:

```groovy
agent { label 'flutter' }
```

The inbound agent port `50000` is available only inside the `jenkins` Docker
network. It does not need to be published on the host. The controller mounts
`/var/run/docker.sock` so Docker Plugin can provision and remove agents.
