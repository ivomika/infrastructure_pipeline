#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"

if [ ! -f .env ]; then
  cp .env.example .env
fi

compose="docker compose --env-file .env -f compose.yaml"

$compose up -d --wait jenkins-docker
$compose exec -T jenkins-docker docker container prune --force
$compose exec -T jenkins-docker docker image prune --force
$compose exec -T jenkins-docker docker builder prune --all --force
