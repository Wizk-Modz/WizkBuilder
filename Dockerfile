# Universal builder for GitHub Actions (GHCR: ghcr.io/wizk-modz/builder)
# Targets: base, cpp-py, full (no .NET)
ARG UBUNTU_VERSION=26.04
ARG NODE_MAJOR=24
ARG GO_VERSION=1.23.12
ARG DOCKER_VERSION=27.3.1
ARG BUILDX_VERSION=v0.17.1
ARG GH_VERSION=2.62.0

FROM ubuntu:${UBUNTU_VERSION} AS base
# Fix locale to avoid warnings
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
# Setup base + non-root user for builds
RUN apt-get update && \
    apt-get -yq upgrade && \
    apt-get install -yq --no-install-recommends sudo lsb-release software-properties-common locales tzdata && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 && \
    (id ubuntu && userdel ubuntu || true) && \
    useradd -u 1001 -U -m -s /bin/bash builder && \
    echo "builder ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder && \
    rm -rf /var/lib/apt/lists/*
USER builder
WORKDIR /home/builder/build
CMD ["bash"]

FROM base AS cpp-py
USER root
# System tools required for GitHub Actions + C/C++ + Python
RUN apt-get update && \
    apt-get install -yq --no-install-recommends \
    git git-lfs curl wget ca-certificates gnupg tar gzip unzip zip jq openssh-client rsync \
    build-essential clang lld lldb cmake ninja-build meson autoconf automake libtool pkg-config ccache \
    libssl-dev zlib1g-dev libcurl4-openssl-dev \
    python3 python3-pip python3-venv python3-dev && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /home/builder/.ccache && chown -R builder:builder /home/builder/.ccache
ENV CCACHE_DIR=/home/builder/.ccache
USER builder
WORKDIR /home/builder/build
CMD ["bash"]

FROM cpp-py AS full
ARG NODE_MAJOR
ARG GO_VERSION
ARG DOCKER_VERSION
ARG BUILDX_VERSION
ARG GH_VERSION
USER root
# Node.js LTS via NodeSource (handles Ubuntu codename automatically)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -yq --no-install-recommends nodejs && \
    node --version && npm --version && \
    npm install -g yarn && \
    rm -rf /var/lib/apt/lists/*
# Go from official tarball
RUN curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz -o /tmp/go.tgz && \
    tar -C /usr/local -xzf /tmp/go.tgz && \
    rm /tmp/go.tgz && \
    /usr/local/go/bin/go version
ENV PATH=/usr/local/go/bin:${PATH}
# Rust via rustup (system-wide, owned by builder)
ENV RUSTUP_HOME=/opt/rustup
ENV CARGO_HOME=/opt/cargo
ENV PATH=/opt/cargo/bin:${PATH}
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable && \
    chown -R builder:builder /opt/rustup /opt/cargo && \
    rustc --version && cargo --version
# Java 21 via Adoptium API tarball (no apt repo needed) + maven/gradle from Ubuntu
RUN curl -fsSL "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse" -o /tmp/jdk.tar.gz && \
    mkdir -p /opt/java-21 && \
    tar -xzf /tmp/jdk.tar.gz -C /opt/java-21 --strip-components=1 && \
    rm /tmp/jdk.tar.gz
ENV JAVA_HOME=/opt/java-21
ENV PATH=/opt/java-21/bin:${PATH}
RUN apt-get update && \
    apt-get install -yq --no-install-recommends maven gradle && \
    rm -rf /var/lib/apt/lists/* && \
    java --version && mvn --version && gradle --version
# Docker CLI (static) + buildx plugin, no daemon
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz -o /tmp/docker.tgz && \
    tar -xzf /tmp/docker.tgz -C /tmp && \
    mv /tmp/docker/docker /usr/local/bin/docker && \
    rm -rf /tmp/docker /tmp/docker.tgz && \
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -fsSL https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64 -o /usr/local/lib/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx && \
    docker --version
# GitHub CLI from release .deb
RUN curl -fsSL https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb -o /tmp/gh.deb && \
    apt-get update && apt-get install -yq /tmp/gh.deb && \
    rm /tmp/gh.deb && rm -rf /var/lib/apt/lists/* && \
    gh --version
USER builder
WORKDIR /home/builder/build
CMD ["bash"]
