#!/usr/bin/env bash
set -euo pipefail

auth_key_path="${JENKINS_AGENT_SSH_PUBLIC_KEY_PATH:-}"

if [[ -z "${auth_key_path}" || ! -f "${auth_key_path}" ]]; then
    echo "Missing SSH public key for Jenkins agent: ${auth_key_path}" >&2
    exit 1
fi

install -d -m 700 -o jenkins -g jenkins /home/jenkins/.ssh
install -m 600 -o jenkins -g jenkins "${auth_key_path}" /home/jenkins/.ssh/authorized_keys
install -d -m 755 -o jenkins -g jenkins /home/jenkins/agent
install -d -m 755 /var/run/sshd

exec /usr/sbin/sshd -D -e
