# Jenkins Docker agents

`compose.agents.yaml` is included by the root `compose.yaml`. It declares
build-only services for three local agent images:

- [`ivomika/flutter-agent:local`](flutter/README.md) with label `flutter`;
- [`ivomika/nodejs-agent:local`](nodejs/README.md) with label `nodejs`;
- [`ivomika/java-agent:local`](java/README.md) with labels `java`, `maven`, and `backend`.

Jenkins Docker Plugin creates and removes the actual agent containers on
demand.

Base images, agent image names, toolchain versions, artifact URLs, and archive
checksums are pinned in [`../toolchain.lock`](../toolchain.lock).
The Node.js agent contains Node.js LTS and npm. The Java agent contains JDK 21,
Maven, and utilities required by Maven Wrapper and Gradle Wrapper.

Build the agent and controller images:

```powershell
docker compose --profile agent-image build
```

Start Jenkins:

```powershell
docker compose up -d jenkins
```

Pipelines request an ephemeral agent by label:

```groovy
agent { label 'flutter' }
```

```groovy
agent { label 'nodejs' }
```

```groovy
agent { label 'java' }
```

The Java agent also accepts the `maven` and `backend` labels.

Minimal Node.js backend pipeline:

```groovy
@Library('jenkins_libs') _

pipeline {
  agent { label 'nodejs' }

  stages {
    stage('Build and test') {
      steps {
        npmInstall()
        npmTest()
        npmBuild()
      }
    }
  }
}
```

Minimal Maven backend pipeline:

```groovy
@Library('jenkins_libs') _

pipeline {
  agent { label 'java' }

  stages {
    stage('Build and test') {
      steps {
        mavenBuild()
      }
    }
  }
}
```

`mavenBuild()` automatically uses Maven Wrapper when present. For a repository
with Gradle Wrapper, use `gradleBuild()`.

The inbound agent port `50000` is available only inside the `jenkins` Docker
network. It does not need to be published on the host.

The controller connects to Docker through `docker-socket-proxy` on the isolated
`docker-api` network. Only the proxy mounts `/var/run/docker.sock`; the Jenkins
controller runs as the image's unprivileged `jenkins` user.

The proxy uses the pinned HAProxy template in `jenkins/docker-socket-proxy`.
Client connections are explicitly closed after each Docker API response so the
Jenkins Docker client cannot reuse an expired idle connection during agent
cleanup.
