#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

env_file=${ENV_FILE:-.env}

compose() {
  docker compose --env-file "$env_file" -f compose.yaml "$@"
}

compose exec -T jenkins-docker sh -c '
  docker build \
    --tag "$JENKINS_AGENT_SLAVE_IMAGE" \
    --file /workspace/jenkins/agents/slave/dockerfile \
    /workspace/jenkins/agents/slave
'

compose exec -T jenkins-docker sh -c '
  docker build \
    --tag "$JENKINS_AGENT_JAVA_IMAGE" \
    --build-arg JENKINS_AGENT_SLAVE_IMAGE="$JENKINS_AGENT_SLAVE_IMAGE" \
    --file /workspace/jenkins/agents/java/dockerfile \
    /workspace/jenkins/agents/java
'

compose exec -T jenkins-docker sh -c '
  docker build \
    --tag "$JENKINS_AGENT_NODE_IMAGE" \
    --build-arg JENKINS_AGENT_SLAVE_IMAGE="$JENKINS_AGENT_SLAVE_IMAGE" \
    --file /workspace/jenkins/agents/node/dockerfile \
    /workspace/jenkins/agents/node
'

compose exec -T jenkins-docker sh -c '
  docker build \
    --tag "$JENKINS_AGENT_FLUTTER_IMAGE" \
    --build-arg JENKINS_AGENT_SLAVE_IMAGE="$JENKINS_AGENT_SLAVE_IMAGE" \
    --file /workspace/jenkins/agents/flutter/dockerfile \
    /workspace/jenkins/agents/flutter
'
