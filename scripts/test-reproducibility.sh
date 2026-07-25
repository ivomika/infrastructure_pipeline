#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${REPRO_PLATFORM:-linux/amd64}"
dry_run=false

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
  shift
fi
[[ "$#" -eq 0 ]] || {
  echo "Usage: $0 [--dry-run]" >&2
  exit 2
}

for command in docker git jq tar diff; do
  command -v "$command" >/dev/null || {
    echo "test-reproducibility: required command is unavailable: $command" >&2
    exit 1
  }
done
docker buildx version >/dev/null

compose_json="$(mktemp)"
work_dir="$(mktemp -d)"
run_id="${CI_RUN_ID:-local}-$$"
run_id="$(tr -cd 'a-zA-Z0-9_.-' <<<"$run_id")"
builder_a="repro-a-${run_id}"
builder_b="repro-b-${run_id}"

cleanup() {
  docker buildx rm "$builder_a" >/dev/null 2>&1 || true
  docker buildx rm "$builder_b" >/dev/null 2>&1 || true
  rm -f "$compose_json"
  if [[ -n "$work_dir" && -d "$work_dir" ]]; then
    rm -rf -- "$work_dir"
  fi
}
trap cleanup EXIT

cd "$project_dir"
source_date_epoch="$(git log -1 --format=%ct)"
[[ "$source_date_epoch" =~ ^[0-9]+$ && "$source_date_epoch" -gt 0 ]] || {
  echo "test-reproducibility: cannot determine commit timestamp" >&2
  exit 1
}
export SOURCE_DATE_EPOCH="$source_date_epoch"
docker compose --profile agent-image config --format json >"$compose_json"

services=()
while IFS= read -r service; do
  services+=("$service")
done < <(
  jq -r '.services | to_entries[] | select(.value.build != null) | .key' \
    "$compose_json" |
    sort
)
[[ "${#services[@]}" -gt 0 ]] || {
  echo "test-reproducibility: Compose contains no build targets" >&2
  exit 1
}

build_image() {
  local builder="$1"
  local run="$2"
  local service="$3"
  local context dockerfile archive
  local -a build_args

  context="$(jq -r --arg service "$service" '.services[$service].build.context' "$compose_json")"
  dockerfile="$(jq -r --arg service "$service" '.services[$service].build.dockerfile' "$compose_json")"
  archive="${work_dir}/${run}/${service}.tar"
  mkdir -p "${work_dir}/${run}"

  build_args=()
  while IFS=$'\t' read -r key value; do
    build_args+=(--build-arg "${key}=${value}")
  done < <(
    jq -r --arg service "$service" \
      '.services[$service].build.args | to_entries[] | [.key, .value] | @tsv' \
      "$compose_json"
  )

  echo "test-reproducibility: building $service with $builder"
  docker buildx build \
    --builder "$builder" \
    --file "${context}/${dockerfile}" \
    --platform "$platform" \
    --no-cache \
    --pull \
    --provenance=false \
    --output "type=oci,dest=${archive},rewrite-timestamp=true" \
    "${build_args[@]}" \
    "$context"
}

write_metadata() {
  local archive="$1"
  local destination="$2"
  local unpack_dir manifest_digest manifest_hash manifest_file

  unpack_dir="$(mktemp -d "${work_dir}/oci.XXXXXX")"
  tar -xf "$archive" -C "$unpack_dir"
  manifest_digest="$(jq -r '.manifests[0].digest' "${unpack_dir}/index.json")"
  manifest_hash="${manifest_digest#sha256:}"
  manifest_file="${unpack_dir}/blobs/sha256/${manifest_hash}"

  {
    echo "manifest ${manifest_digest}"
    jq -r '"config \(.config.digest) \(.config.size) \(.config.mediaType)"' \
      "$manifest_file"
    jq -r '.layers[] | "layer \(.digest) \(.size) \(.mediaType)"' \
      "$manifest_file"
  } >"$destination"

  rm -rf -- "$unpack_dir"
}

if $dry_run; then
  printf 'test-reproducibility: targets for %s:' "$platform"
  printf ' %s' "${services[@]}"
  echo
  exit 0
fi

"${project_dir}/scripts/verify-locks.sh"

docker buildx create --name "$builder_a" --driver docker-container >/dev/null
docker buildx create --name "$builder_b" --driver docker-container >/dev/null
docker buildx inspect --builder "$builder_a" --bootstrap >/dev/null
docker buildx inspect --builder "$builder_b" --bootstrap >/dev/null

for service in "${services[@]}"; do
  build_image "$builder_a" run-a "$service"
  build_image "$builder_b" run-b "$service"

  metadata_a="${work_dir}/run-a/${service}.metadata"
  metadata_b="${work_dir}/run-b/${service}.metadata"
  write_metadata "${work_dir}/run-a/${service}.tar" "$metadata_a"
  write_metadata "${work_dir}/run-b/${service}.tar" "$metadata_b"

  if ! diff -u "$metadata_a" "$metadata_b"; then
    echo "test-reproducibility: OCI metadata differs for $service" >&2
    exit 1
  fi
  echo "test-reproducibility: $service is reproducible"
done

echo "test-reproducibility: every image produced identical OCI digests"
