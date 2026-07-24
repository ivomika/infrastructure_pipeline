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
network. It does not need to be published on the host.

The controller connects to Docker through `docker-socket-proxy` on the isolated
`docker-api` network. Only the proxy mounts `/var/run/docker.sock`; the Jenkins
controller runs as the image's unprivileged `jenkins` user.

The proxy uses the pinned HAProxy template in `jenkins/docker-socket-proxy`.
Client connections are explicitly closed after each Docker API response so the
Jenkins Docker client cannot reuse an expired idle connection during agent
cleanup.
