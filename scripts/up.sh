#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

if [ ! -f .env ]; then
  cp .env.example .env
fi

docker compose --env-file .env -f compose.yaml build
docker compose --env-file .env -f compose.yaml up -d --wait jenkins-docker
./scripts/build-jenkins-agents.sh
docker compose --env-file .env -f compose.yaml up -d
