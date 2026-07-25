#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
private_key="${project_dir}/jenkins/secrets/shared-library.key"
known_hosts="${project_dir}/jenkins/secrets/known_hosts"

fail() {
  echo "preflight-secrets: $*" >&2
  exit 1
}

[[ -s "$private_key" ]] || fail "jenkins/secrets/shared-library.key is missing or empty"
[[ -s "$known_hosts" ]] || fail "jenkins/secrets/known_hosts is missing or empty"

first_line="$(head -n 1 "$private_key")"
[[ "$first_line" =~ ^-----BEGIN[[:space:]].*PRIVATE[[:space:]]KEY-----$ ]] ||
  fail "shared-library.key is not an SSH private key"

if stat -f '%Lp' "$private_key" >/dev/null 2>&1; then
  key_mode="$(stat -f '%Lp' "$private_key")"
else
  key_mode="$(stat -c '%a' "$private_key")"
fi
key_mode="${key_mode: -3}"
(( (8#${key_mode} & 077) == 0 )) ||
  fail "shared-library.key must not be readable or writable by group/other (mode: $key_mode)"

valid_host_count="$(
  awk '
    /^[[:space:]]*(#|$)/ { next }
    NF < 3 { invalid=1; next }
    { valid++ }
    END {
      if (invalid) exit 1
      print valid + 0
    }
  ' "$known_hosts"
)" || fail "known_hosts contains an invalid entry"
[[ "$valid_host_count" -gt 0 ]] || fail "known_hosts contains no host keys"

echo "preflight-secrets: runtime SSH secrets are valid"
