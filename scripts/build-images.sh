#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

source_date_epoch="$(git log -1 --format=%ct)"
[[ "$source_date_epoch" =~ ^[0-9]+$ && "$source_date_epoch" -gt 0 ]] || {
  echo "build-images: cannot determine the current commit timestamp" >&2
  exit 1
}

export SOURCE_DATE_EPOCH="$source_date_epoch"
export BUILDX_NO_DEFAULT_ATTESTATIONS=1
exec docker compose --profile agent-image build "$@"
