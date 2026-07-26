#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
toolchain_lock="${project_dir}/jenkins/toolchain.lock"
direct_plugins="${project_dir}/jenkins/plugins/plugins.txt"
plugin_lock="${project_dir}/jenkins/plugins/plugins.lock.txt"
plugin_checksums="${project_dir}/jenkins/plugins/plugins.sha256"
online=true

usage() {
  echo "Usage: $0 [--offline]" >&2
}

fail() {
  echo "verify-locks: $*" >&2
  exit 1
}

if [[ "${1:-}" == "--offline" ]]; then
  online=false
  shift
fi
[[ "$#" -eq 0 ]] || {
  usage
  exit 2
}

for file in "$toolchain_lock" "$direct_plugins" "$plugin_lock" "$plugin_checksums"; do
  [[ -s "$file" ]] || fail "missing or empty input: ${file#"$project_dir"/}"
done

invalid_lock_line="$(grep -Ev '^(#.*|[[:space:]]*|[A-Z][A-Z0-9_]*=[^[:space:]]+)$' "$toolchain_lock" || true)"
[[ -z "$invalid_lock_line" ]] || fail "toolchain.lock contains an invalid line: $invalid_lock_line"

set -a
# shellcheck disable=SC1090
source "$toolchain_lock"
set +a

required_values=(
  JENKINS_CONTROLLER_BASE_TAG
  JENKINS_CONTROLLER_BASE_DIGEST
  JENKINS_VERSION
  JENKINS_INBOUND_AGENT_TAG
  JENKINS_INBOUND_AGENT_DIGEST
  JENKINS_INBOUND_AGENT_VERSION
  JENKINS_PLUGIN_DOWNLOAD_URL
  JENKINS_PLUGIN_INFO_URL
  DOCKER_SOCKET_PROXY_TAG
  DOCKER_SOCKET_PROXY_DIGEST
  DOCKER_SOCKET_PROXY_VERSION
  JENKINS_CONTROLLER_IMAGE
  JENKINS_AGENT_BASE_IMAGE
  NODEJS_AGENT_IMAGE
  JAVA_AGENT_IMAGE
  FLUTTER_AGENT_IMAGE
  DEBIAN_CONTROLLER_SNAPSHOT
  DEBIAN_AGENT_SNAPSHOT
  DEBIAN_CA_CERTIFICATES_VERSION
  DEBIAN_CURL_VERSION
  DEBIAN_GIT_VERSION
  DEBIAN_OPENSSH_CLIENT_VERSION
  DEBIAN_LIBGLU1_MESA_VERSION
  DEBIAN_LIBSQLITE3_DEV_VERSION
  DEBIAN_MAKE_VERSION
  DEBIAN_GCC_VERSION
  DEBIAN_GXX_VERSION
  DEBIAN_PYTHON3_VERSION
  DEBIAN_UNZIP_VERSION
  DEBIAN_XZ_UTILS_VERSION
  DEBIAN_ZIP_VERSION
  NODE_VERSION
  NODE_LINUX_X64_URL
  NODE_LINUX_X64_SHA256
  NODE_LINUX_ARM64_URL
  NODE_LINUX_ARM64_SHA256
  MAVEN_VERSION
  MAVEN_URL
  MAVEN_ARCHIVE_SHA512
  FLUTTER_VERSION
  FLUTTER_URL
  FLUTTER_ARCHIVE_SHA256
  ANDROID_COMMAND_LINE_TOOLS_VERSION
  ANDROID_COMMAND_LINE_TOOLS_URL
  ANDROID_COMMAND_LINE_TOOLS_SHA256
  ANDROID_COMMAND_LINE_TOOLS_SHA1
  ANDROID_PLATFORM_VERSION
  ANDROID_BUILD_TOOLS_VERSION
)

for name in "${required_values[@]}"; do
  [[ -n "${!name:-}" ]] || fail "required value is empty: $name"
done

for digest in \
  "$JENKINS_CONTROLLER_BASE_DIGEST" \
  "$JENKINS_INBOUND_AGENT_DIGEST" \
  "$DOCKER_SOCKET_PROXY_DIGEST"; do
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid OCI digest: $digest"
done

for checksum in \
  "$NODE_LINUX_X64_SHA256" \
  "$NODE_LINUX_ARM64_SHA256" \
  "$FLUTTER_ARCHIVE_SHA256" \
  "$ANDROID_COMMAND_LINE_TOOLS_SHA256"; do
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || fail "invalid SHA-256: $checksum"
done
[[ "$MAVEN_ARCHIVE_SHA512" =~ ^[0-9a-f]{128}$ ]] ||
  fail "invalid Maven SHA-512"
[[ "$ANDROID_COMMAND_LINE_TOOLS_SHA1" =~ ^[0-9a-f]{40}$ ]] ||
  fail "invalid Android SHA-1"
[[ "$DEBIAN_CONTROLLER_SNAPSHOT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] ||
  fail "invalid controller Debian snapshot"
[[ "$DEBIAN_AGENT_SNAPSHOT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] ||
  fail "invalid agent Debian snapshot"

for url_name in \
  NODE_LINUX_X64_URL \
  NODE_LINUX_ARM64_URL \
  MAVEN_URL \
  FLUTTER_URL \
  ANDROID_COMMAND_LINE_TOOLS_URL \
  JENKINS_PLUGIN_DOWNLOAD_URL \
  JENKINS_PLUGIN_INFO_URL; do
  url="${!url_name}"
  [[ "$url" == https://* ]] || fail "$url_name must use HTTPS"
done

[[ "$NODE_LINUX_X64_URL" == *"/v${NODE_VERSION}/"*"$NODE_VERSION"*x64* ]] ||
  fail "Node.js x64 URL does not contain the locked version"
[[ "$NODE_LINUX_ARM64_URL" == *"/v${NODE_VERSION}/"*"$NODE_VERSION"*arm64* ]] ||
  fail "Node.js arm64 URL does not contain the locked version"
[[ "$MAVEN_URL" == https://archive.apache.org/*"/${MAVEN_VERSION}/"*"$MAVEN_VERSION"* ]] ||
  fail "Maven URL is not a versioned Apache Archive URL"
[[ "$FLUTTER_URL" == *"flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" ]] ||
  fail "Flutter URL does not contain the locked version"
[[ "$ANDROID_COMMAND_LINE_TOOLS_URL" == *"-${ANDROID_COMMAND_LINE_TOOLS_VERSION}_latest.zip" ]] ||
  fail "Android URL does not contain the locked release ID"

plugin_line_pattern='^[a-z0-9][a-z0-9_.-]*:[^:[:space:]]+$'
grep -Eqv "$plugin_line_pattern" "$direct_plugins" &&
  fail "plugins.txt contains an unpinned or invalid entry"
grep -Eqv "$plugin_line_pattern" "$plugin_lock" &&
  fail "plugins.lock.txt contains an unpinned or invalid entry"

duplicate_plugin="$(cut -d: -f1 "$plugin_lock" | sort | uniq -d | head -n 1)"
[[ -z "$duplicate_plugin" ]] || fail "duplicate plugin in lock: $duplicate_plugin"

while IFS= read -r plugin; do
  grep -Fxq "$plugin" "$plugin_lock" ||
    fail "direct plugin is absent from the resolved lock: $plugin"
done < "$direct_plugins"

grep -Eqv '^[0-9a-f]{64}  [a-z0-9][a-z0-9_.-]*\.jpi$' "$plugin_checksums" &&
  fail "plugins.sha256 contains an invalid entry"

lock_ids="$(mktemp)"
checksum_ids="$(mktemp)"
cleanup() {
  rm -f "$lock_ids" "$checksum_ids"
}
trap cleanup EXIT

cut -d: -f1 "$plugin_lock" | sort >"$lock_ids"
awk '{ sub(/\.jpi$/, "", $2); print $2 }' "$plugin_checksums" | sort >"$checksum_ids"
cmp -s "$lock_ids" "$checksum_ids" ||
  fail "plugin lock and checksum file contain different plugin sets"

if ! $online; then
  echo "verify-locks: offline validation passed"
  exit 0
fi

for command in curl docker python3; do
  command -v "$command" >/dev/null || fail "required command is unavailable: $command"
done
docker buildx version >/dev/null 2>&1 || fail "Docker Buildx is unavailable"

verify_image_digest() {
  local tag="$1"
  local expected="$2"
  local actual
  actual="$(docker buildx imagetools inspect "$tag" |
    awk '/^Digest:/ && !found { value=$2; found=1 } END { print value }')"
  [[ "$actual" == "$expected" ]] ||
    fail "registry digest changed for $tag: expected $expected, got ${actual:-none}"
}

verify_url() {
  curl --head --fail --location --silent --show-error \
    --retry 3 --retry-all-errors --connect-timeout 15 \
    --max-time 90 --output /dev/null "$1"
}

verify_image_digest "$JENKINS_CONTROLLER_BASE_TAG" "$JENKINS_CONTROLLER_BASE_DIGEST"
verify_image_digest "$JENKINS_INBOUND_AGENT_TAG" "$JENKINS_INBOUND_AGENT_DIGEST"
verify_image_digest "$DOCKER_SOCKET_PROXY_TAG" "$DOCKER_SOCKET_PROXY_DIGEST"

for url in \
  "$NODE_LINUX_X64_URL" \
  "$NODE_LINUX_ARM64_URL" \
  "$MAVEN_URL" \
  "$FLUTTER_URL" \
  "$ANDROID_COMMAND_LINE_TOOLS_URL"; do
  verify_url "$url"
done

node_manifest="$(curl --fail --location --silent --show-error \
  "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt")"
for node_url_name in NODE_LINUX_X64_URL NODE_LINUX_ARM64_URL; do
  node_url="${!node_url_name}"
  node_checksum_name="${node_url_name%_URL}_SHA256"
  node_file="${node_url##*/}"
  official="$(awk -v file="$node_file" '$2 == file { print $1; exit }' <<<"$node_manifest")"
  [[ "$official" == "${!node_checksum_name}" ]] ||
    fail "official Node.js checksum mismatch for $node_file"
done

official_maven="$(curl --fail --location --silent --show-error "${MAVEN_URL}.sha512" |
  awk 'NR == 1 { value=tolower($1) } END { print value }')"
[[ "$official_maven" == "$MAVEN_ARCHIVE_SHA512" ]] ||
  fail "official Maven checksum mismatch"

curl --fail --location --silent --show-error \
  "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" |
  python3 -c '
import json, os, sys
data = json.load(sys.stdin)
url = os.environ["FLUTTER_URL"]
expected = os.environ["FLUTTER_ARCHIVE_SHA256"]
archive = url.split("/releases/", 1)[-1]
matches = [item for item in data["releases"] if item.get("archive") == archive]
if len(matches) != 1 or matches[0].get("sha256") != expected:
    raise SystemExit("verify-locks: official Flutter checksum mismatch")
'

curl --fail --location --silent --show-error \
  "https://dl.google.com/android/repository/repository2-3.xml" |
  python3 -c '
import os, sys, xml.etree.ElementTree as ET
root = ET.parse(sys.stdin).getroot()
filename = os.environ["ANDROID_COMMAND_LINE_TOOLS_URL"].rsplit("/", 1)[-1]
expected = os.environ["ANDROID_COMMAND_LINE_TOOLS_SHA1"]
found = None
for archive in root.iter():
    if not archive.tag.endswith("archive"):
        continue
    url = next((x.text for x in archive.iter() if x.tag.endswith("url")), None)
    if url != filename:
        continue
    for item in archive.iter():
        if item.tag.endswith("checksum") and item.attrib.get("type") == "sha1":
            found = item.text
            break
if found != expected:
    raise SystemExit("verify-locks: official Android checksum mismatch")
'

curl --fail --location --silent --show-error "$JENKINS_PLUGIN_INFO_URL" |
  python3 -c '
import base64, hashlib, json, pathlib, sys
metadata = json.load(sys.stdin)["plugins"]
root = pathlib.Path(sys.argv[1])
versions = {}
for line in (root / "plugins.lock.txt").read_text().splitlines():
    plugin, version = line.split(":", 1)
    versions[plugin] = version
checksums = {}
for line in (root / "plugins.sha256").read_text().splitlines():
    checksum, filename = line.split()
    checksums[filename.removesuffix(".jpi")] = checksum
for plugin, version in versions.items():
    encoded = metadata.get(plugin, {}).get(version, {}).get("sha256")
    if not encoded:
        raise SystemExit(f"verify-locks: no official checksum for {plugin}:{version}")
    official = base64.b64decode(encoded).hex()
    if official != checksums[plugin]:
        raise SystemExit(f"verify-locks: official plugin checksum mismatch for {plugin}:{version}")
' "${project_dir}/jenkins/plugins"

first_plugin="$(head -n 1 "$plugin_lock")"
first_plugin_id="${first_plugin%%:*}"
first_plugin_version="${first_plugin#*:}"
verify_url \
  "${JENKINS_PLUGIN_DOWNLOAD_URL}/${first_plugin_id}/${first_plugin_version}/${first_plugin_id}.hpi"

echo "verify-locks: online validation passed"
