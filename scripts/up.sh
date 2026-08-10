#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

env_file=${1:-.env}
example_file="${env_file}.example"

if [ ! -f "$env_file" ]; then
  cp "$example_file" "$env_file"
fi

compose() {
  docker compose --env-file "$env_file" -f compose.yaml "$@"
}

compose build
compose up -d --wait jenkins-docker
ENV_FILE="$env_file" ./scripts/build-jenkins-agents.sh
compose up -d
