FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG FLUTTER_VERSION=3.44.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      libglu1-mesa \
      libsqlite3-dev \
      openjdk-17-jdk \
      openssh-server \
      sqlite3 \
      sudo \
      unzip \
      xz-utils \
      zip \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/jenkins -s /bin/bash jenkins \
    && echo 'jenkins ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/jenkins \
    && chmod 0440 /etc/sudoers.d/jenkins \
    && mkdir -p /var/run/sshd /home/jenkins/agent /opt/flutter \
    && sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/^UsePAM yes/UsePAM yes/' /etc/ssh/sshd_config \
    && printf '\nPermitRootLogin no\nPasswordAuthentication yes\nPubkeyAuthentication yes\n' >> /etc/ssh/sshd_config \
    && chown -R jenkins:jenkins /home/jenkins /opt/flutter

RUN curl -fL --retry 5 --retry-all-errors --connect-timeout 20 \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && chown -R jenkins:jenkins /opt/flutter /home/jenkins

ENV FLUTTER_HOME=/opt/flutter
ENV PATH=/opt/flutter/bin:/usr/lib/jvm/java-17-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PUB_CACHE=/home/jenkins/.pub-cache
ENV CI=true
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

COPY agents/common/ssh-agent-entrypoint.sh /usr/local/bin/ssh-agent-entrypoint.sh
RUN chmod +x /usr/local/bin/ssh-agent-entrypoint.sh

RUN su - jenkins -c 'flutter config --no-analytics' \
    && su - jenkins -c 'dart --disable-analytics' \
    && su - jenkins -c 'flutter precache --linux'

EXPOSE 22

ENTRYPOINT ["/usr/local/bin/ssh-agent-entrypoint.sh"]
