#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

env_file=${ENV_FILE:-.env}
example_file="${env_file}.example"

if [ ! -f "$env_file" ]; then
  cp "$example_file" "$env_file"
fi

compose() {
  docker compose --env-file "$env_file" -f compose.yaml "$@"
}

compose up -d --wait jenkins-docker
compose exec -T jenkins-docker docker container prune --force
compose exec -T jenkins-docker docker image prune --force
compose exec -T jenkins-docker docker builder prune --all --force
