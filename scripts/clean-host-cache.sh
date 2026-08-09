#!/usr/bin/env sh
set -eu

docker image prune --force
docker builder prune --all --force
