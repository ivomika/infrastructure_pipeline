#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain_lock="${project_dir}/jenkins/toolchain.lock"
direct_plugins="${project_dir}/jenkins/plugins/plugins.txt"
plugin_lock="${project_dir}/jenkins/plugins/plugins.lock.txt"
plugin_checksums="${project_dir}/jenkins/plugins/plugins.sha256"
check_only=false

usage() {
  echo "Usage: $0 [--check]" >&2
}

fail() {
  echo "refresh-locks: $*" >&2
  exit 1
}

if [[ "${1:-}" == "--check" ]]; then
  check_only=true
  shift
fi
[[ "$#" -eq 0 ]] || {
  usage
  exit 2
}

for command in curl docker python3; do
  command -v "$command" >/dev/null ||
    fail "required command is unavailable: $command"
done
docker buildx version >/dev/null 2>&1 ||
  fail "Docker Buildx is unavailable"
if command -v sha256sum >/dev/null 2>&1; then
  sha256_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  sha256_command=(shasum -a 256)
else
  fail "sha256sum or shasum is required"
fi

for file in "$toolchain_lock" "$direct_plugins"; do
  [[ -s "$file" ]] || fail "missing or empty input: ${file#"$project_dir"/}"
done

work_dir="$(mktemp -d)"
updated_toolchain="${work_dir}/toolchain.lock"
updated_plugin_lock="${work_dir}/plugins.lock.txt"
updated_plugin_checksums="${work_dir}/plugins.sha256"
cp "$toolchain_lock" "$updated_toolchain"

cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT

replace_value() {
  local name="$1"
  local value="$2"
  local output="${work_dir}/toolchain.next"

  [[ -n "$value" && "$value" != *$'\n'* ]] ||
    fail "cannot write an empty or multiline value for $name"
  awk -v name="$name" -v value="$value" '
    index($0, name "=") == 1 {
      print name "=" value
      found=1
      next
    }
    { print }
    END {
      if (!found) exit 3
    }
  ' "$updated_toolchain" >"$output" ||
    fail "cannot replace $name in toolchain.lock"
  mv "$output" "$updated_toolchain"
}

load_toolchain() {
  set -a
  # shellcheck disable=SC1090
  source "$updated_toolchain"
  set +a
}

registry_digest() {
  local tag="$1"
  local digest

  digest="$(
    docker buildx imagetools inspect "$tag" |
      awk '/^Digest:/ && !found { print $2; found=1 }'
  )"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] ||
    fail "cannot resolve registry digest for $tag"
  printf '%s' "$digest"
}

download() {
  curl --fail --location --silent --show-error \
    --retry 3 --retry-all-errors --connect-timeout 15 \
    --max-time 900 "$@"
}

load_toolchain

replace_value \
  JENKINS_CONTROLLER_BASE_DIGEST \
  "$(registry_digest "$JENKINS_CONTROLLER_BASE_TAG")"
replace_value \
  JENKINS_INBOUND_AGENT_DIGEST \
  "$(registry_digest "$JENKINS_INBOUND_AGENT_TAG")"
replace_value \
  DOCKER_SOCKET_PROXY_DIGEST \
  "$(registry_digest "$DOCKER_SOCKET_PROXY_TAG")"
load_toolchain

jenkins_version="$(
  docker run --rm \
    --entrypoint sh \
    "${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}" \
    -c 'printf "%s" "$JENKINS_VERSION"'
)"
[[ "$jenkins_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
  fail "cannot determine Jenkins version from the controller image"
replace_value JENKINS_VERSION "$jenkins_version"

inbound_tag="${JENKINS_INBOUND_AGENT_TAG##*:}"
replace_value JENKINS_INBOUND_AGENT_VERSION "${inbound_tag%-jdk*}"
proxy_tag="${DOCKER_SOCKET_PROXY_TAG##*:}"
replace_value DOCKER_SOCKET_PROXY_VERSION "${proxy_tag#v}"

node_manifest="${work_dir}/node-shasums.txt"
node_x64_file="node-v${NODE_VERSION}-linux-x64.tar.xz"
node_arm64_file="node-v${NODE_VERSION}-linux-arm64.tar.xz"
node_x64_url="https://nodejs.org/dist/v${NODE_VERSION}/${node_x64_file}"
node_arm64_url="https://nodejs.org/dist/v${NODE_VERSION}/${node_arm64_file}"
download \
  "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
  --output "$node_manifest"
node_x64_sha256="$(
  awk -v file="$node_x64_file" '$2 == file { print $1; exit }' "$node_manifest"
)"
node_arm64_sha256="$(
  awk -v file="$node_arm64_file" '$2 == file { print $1; exit }' "$node_manifest"
)"
[[ "$node_x64_sha256" =~ ^[0-9a-f]{64}$ ]] ||
  fail "official checksum is missing for $node_x64_file"
[[ "$node_arm64_sha256" =~ ^[0-9a-f]{64}$ ]] ||
  fail "official checksum is missing for $node_arm64_file"
replace_value NODE_LINUX_X64_URL "$node_x64_url"
replace_value NODE_LINUX_X64_SHA256 "$node_x64_sha256"
replace_value NODE_LINUX_ARM64_URL "$node_arm64_url"
replace_value NODE_LINUX_ARM64_SHA256 "$node_arm64_sha256"

maven_major="${MAVEN_VERSION%%.*}"
maven_url="https://archive.apache.org/dist/maven/maven-${maven_major}/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
maven_sha512="$(
  download "${maven_url}.sha512" |
    awk 'NR == 1 { print tolower($1); exit }'
)"
[[ "$maven_sha512" =~ ^[0-9a-f]{128}$ ]] ||
  fail "official Maven checksum is missing for $MAVEN_VERSION"
replace_value MAVEN_URL "$maven_url"
replace_value MAVEN_ARCHIVE_SHA512 "$maven_sha512"

flutter_releases="${work_dir}/flutter-releases.json"
download \
  "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" \
  --output "$flutter_releases"
flutter_metadata="$(
  python3 - "$flutter_releases" "$FLUTTER_VERSION" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    releases = json.load(stream)["releases"]
version = sys.argv[2]
matches = [
    item
    for item in releases
    if item.get("version") == version
    and item.get("channel") == "stable"
    and item.get("archive", "").startswith("stable/linux/")
]
if len(matches) != 1:
    raise SystemExit(
        f"refresh-locks: expected one stable Linux Flutter release for {version}"
    )
item = matches[0]
print(item["archive"], item["sha256"], sep="\t")
PY
)"
IFS=$'\t' read -r flutter_archive flutter_sha256 <<<"$flutter_metadata"
[[ "$flutter_sha256" =~ ^[0-9a-f]{64}$ ]] ||
  fail "official Flutter checksum is missing for $FLUTTER_VERSION"
replace_value \
  FLUTTER_URL \
  "https://storage.googleapis.com/flutter_infra_release/releases/${flutter_archive}"
replace_value FLUTTER_ARCHIVE_SHA256 "$flutter_sha256"

android_file="commandlinetools-linux-${ANDROID_COMMAND_LINE_TOOLS_VERSION}_latest.zip"
android_url="https://dl.google.com/android/repository/${android_file}"
android_archive="${work_dir}/${android_file}"
android_repository="${work_dir}/android-repository.xml"
download "$android_url" --output "$android_archive"
android_sha256="$("${sha256_command[@]}" "$android_archive" | awk '{ print $1 }')"
download \
  "https://dl.google.com/android/repository/repository2-3.xml" \
  --output "$android_repository"
android_sha1="$(
  python3 - "$android_repository" "$android_file" <<'PY'
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
filename = sys.argv[2]
matches = []
for archive in root.iter():
    if not archive.tag.endswith("archive"):
        continue
    url = next((item.text for item in archive.iter() if item.tag.endswith("url")), None)
    if url != filename:
        continue
    checksum = next(
        (
            item.text
            for item in archive.iter()
            if item.tag.endswith("checksum") and item.attrib.get("type") == "sha1"
        ),
        None,
    )
    if checksum:
        matches.append(checksum)
if len(set(matches)) != 1:
    raise SystemExit(
        f"refresh-locks: expected one official Android SHA-1 for {filename}"
    )
print(matches[0])
PY
)"
[[ "$android_sha256" =~ ^[0-9a-f]{64}$ ]] ||
  fail "cannot calculate Android SHA-256"
[[ "$android_sha1" =~ ^[0-9a-f]{40}$ ]] ||
  fail "official Android SHA-1 is missing"
replace_value ANDROID_COMMAND_LINE_TOOLS_URL "$android_url"
replace_value ANDROID_COMMAND_LINE_TOOLS_SHA256 "$android_sha256"
replace_value ANDROID_COMMAND_LINE_TOOLS_SHA1 "$android_sha1"

load_toolchain
plugin_resolution="$(
  docker run --rm \
    --entrypoint jenkins-plugin-cli \
    --volume "${direct_plugins}:/locks/plugins.txt:ro" \
    "${JENKINS_CONTROLLER_BASE_TAG}@${JENKINS_CONTROLLER_BASE_DIGEST}" \
    --hide-security-warnings \
    --jenkins-plugin-info "$JENKINS_PLUGIN_INFO_URL" \
    --jenkins-update-center-download-url "$JENKINS_PLUGIN_DOWNLOAD_URL" \
    --jenkins-version "$JENKINS_VERSION" \
    --latest true \
    --list \
    --no-download \
    --plugin-file /locks/plugins.txt
)"

awk '
  /^Resulting plugin list:$/ {
    capture=1
    next
  }
  capture && /^[a-z0-9][a-z0-9_.-]* [^[:space:]]+$/ {
    print $1 ":" $2
    count++
    next
  }
  capture && count {
    exit
  }
' <<<"$plugin_resolution" |
  sort -t: -k1,1 >"$updated_plugin_lock"
plugin_count="$(wc -l <"$updated_plugin_lock" | tr -d ' ')"
[[ "$plugin_count" -gt 0 ]] ||
  fail "Jenkins plugin resolver produced an empty lock"

plugin_metadata="${work_dir}/plugin-versions.json"
download "$JENKINS_PLUGIN_INFO_URL" --output "$plugin_metadata"
python3 - "$plugin_metadata" "$updated_plugin_lock" >"$updated_plugin_checksums" <<'PY'
import base64
import hashlib
import json
import pathlib
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    metadata = json.load(stream)["plugins"]
lock = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines()

for line in lock:
    plugin, version = line.split(":", 1)
    encoded = metadata.get(plugin, {}).get(version, {}).get("sha256")
    if not encoded:
        raise SystemExit(
            f"refresh-locks: no official checksum for {plugin}:{version}"
        )
    digest = base64.b64decode(encoded)
    if len(digest) != hashlib.sha256().digest_size:
        raise SystemExit(
            f"refresh-locks: invalid official checksum for {plugin}:{version}"
        )
    print(f"{digest.hex()}  {plugin}.jpi")
PY
sort -k2,2 -o "$updated_plugin_checksums" "$updated_plugin_checksums"

if $check_only; then
  stale=false
  for pair in \
    "$toolchain_lock:$updated_toolchain" \
    "$plugin_lock:$updated_plugin_lock" \
    "$plugin_checksums:$updated_plugin_checksums"; do
    current="${pair%%:*}"
    updated="${pair#*:}"
    if ! cmp -s "$current" "$updated"; then
      diff -u "$current" "$updated" || true
      stale=true
    fi
  done
  $stale && fail "generated lock data is stale"
  echo "refresh-locks: lock data is current ($plugin_count plugins)"
  exit 0
fi

install -m 644 "$updated_toolchain" "$toolchain_lock"
install -m 644 "$updated_plugin_lock" "$plugin_lock"
install -m 644 "$updated_plugin_checksums" "$plugin_checksums"
"${project_dir}/scripts/verify-locks.sh" --offline
echo "refresh-locks: updated toolchain and $plugin_count plugin locks"
