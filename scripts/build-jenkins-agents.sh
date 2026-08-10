#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

env_file=${ENV_FILE:-.env}

compose() {
  docker compose --env-file "$env_file" -f compose.yaml "$@"
}

compose exec -T jenkins-docker docker build \
  --tag devops-infra/jenkins-agent-slave:1.0.0 \
  --file /workspace/jenkins/agents/slave/dockerfile \
  /workspace/jenkins/agents/slave

compose exec -T jenkins-docker docker build \
  --tag devops-infra/jenkins-agent-java:1.0.0 \
  --file /workspace/jenkins/agents/java/dockerfile \
  /workspace/jenkins/agents/java

compose exec -T jenkins-docker docker build \
  --tag devops-infra/jenkins-agent-node:1.0.0 \
  --file /workspace/jenkins/agents/node/dockerfile \
  /workspace/jenkins/agents/node

compose exec -T jenkins-docker docker build \
  --tag devops-infra/jenkins-agent-flutter:1.0.0 \
  --file /workspace/jenkins/agents/flutter/dockerfile \
  /workspace/jenkins/agents/flutter
