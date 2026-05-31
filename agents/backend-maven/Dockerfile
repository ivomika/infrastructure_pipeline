FROM maven:3.9.11-eclipse-temurin-17

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      git \
      openssh-server \
      sqlite3 \
      libsqlite3-dev \
      sudo \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /home/jenkins/agent \
    && useradd -m -d /home/jenkins -s /bin/bash jenkins \
    && echo 'jenkins ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/jenkins \
    && chmod 0440 /etc/sudoers.d/jenkins \
    && sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^UsePAM yes/UsePAM yes/' /etc/ssh/sshd_config \
    && printf '\nPermitRootLogin no\nPasswordAuthentication yes\nPubkeyAuthentication yes\n' >> /etc/ssh/sshd_config \
    && chown -R jenkins:jenkins /home/jenkins

COPY agents/common/ssh-agent-entrypoint.sh /usr/local/bin/ssh-agent-entrypoint.sh
RUN chmod +x /usr/local/bin/ssh-agent-entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/ssh-agent-entrypoint.sh"]
