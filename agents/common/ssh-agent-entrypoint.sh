#!/usr/bin/env bash
set -euo pipefail

AGENT_SSH_USERNAME="${AGENT_SSH_USERNAME:-jenkins}"
AGENT_SSH_PASSWORD="${AGENT_SSH_PASSWORD:-jenkins123}"

if ! id "${AGENT_SSH_USERNAME}" >/dev/null 2>&1; then
  useradd -m -d "/home/${AGENT_SSH_USERNAME}" -s /bin/bash "${AGENT_SSH_USERNAME}"
fi

echo "${AGENT_SSH_USERNAME}:${AGENT_SSH_PASSWORD}" | chpasswd
mkdir -p /var/run/sshd "/home/${AGENT_SSH_USERNAME}/agent"
chown -R "${AGENT_SSH_USERNAME}:${AGENT_SSH_USERNAME}" "/home/${AGENT_SSH_USERNAME}"

exec /usr/sbin/sshd -D -e

