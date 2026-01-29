# syntax=docker/dockerfile:latest
ARG UBUNTU_VERSION=noble
ARG AFLPP_VERSION=4.35c
ARG MUSL_TOOLCHAIN=arm-linux-musleabi-native
ARG GHIDRA_VERSION=12.0.1_PUBLIC
ARG GHIDRA_SHA=85bd2990945f3a78df4d1e09f1bb1f40ab77be3bac62c6e7678900788c7f0f41
ARG GHIDRA_URL=https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.0.1_build/ghidra_12.0.1_PUBLIC_20260114.zip
ARG GHIDRATHON_SHA=0aff06f88f04e55d90b0504577ed6a9712ff095cef5ad9c829f27fcb31399f56
ARG GHIDRATHON_URL=https://github.com/mandiant/Ghidrathon/releases/download/v4.0.0/Ghidrathon-v4.0.0.zip


################################################################################
# Download and decompress musl toolchain for use in the final SURGEON image    #
################################################################################
FROM alpine:latest AS musl-toolchain-downloader
ARG MUSL_TOOLCHAIN

# Download and decompression step because ADD cannot (yet) do both at once
ADD --link https://musl.cc/$MUSL_TOOLCHAIN.tgz /

RUN tar -xf /$MUSL_TOOLCHAIN.tgz


################################################################################
# Create the Python venv for use in the final image                            #
# Using a different target allows us to make use of the Docker build cache for #
# the final venv, avoiding the frequent rebuild of keystone-engine             #
################################################################################
FROM --platform=linux/arm64 ubuntu:$UBUNTU_VERSION AS python-builder

# Enable APT package caching
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install base packages (including arm32 libraries and headers)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        make \
        cmake \
        python3-minimal \
        python3-pip \
        python3-venv

# Install Python dependencies for all modules into the venv (see wildcard below)
RUN --mount=type=bind,source=src,target=/src \
    --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    python3 -m venv /root/.venv && \
    . /root/.venv/bin/activate && \
    pip3 install -U \
        wheel \
        meson && \
    for req in /src/*/requirements.txt; do \
        pip3 install -r $req; \
    done


################################################################################
# Final SURGEON debugger image                                                 #
################################################################################
FROM ubuntu:$UBUNTU_VERSION AS debugger

# Enable APT package caching
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install base packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3-minimal \
        binutils \
        gdb-multiarch && \
    if [ "$(uname -m)" = "aarch64" ]; then \
        apt-get install -y --no-install-recommends gdbserver; \
    else \
        apt-get install -y --no-install-recommends qemu-user; \
    fi

# Copy entrypoint in
COPY --link --chmod=0755 docker/debugger-entrypoint.sh /debugger-entrypoint.sh
COPY --link --chmod=0755 docker/trace-entrypoint.sh /trace-entrypoint.sh

# Expose port for the debugger to connect to
EXPOSE 1234

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/debugger-entrypoint.sh"]


################################################################################
# Final SURGEON runner image                                                   #
################################################################################
FROM --platform=linux/arm64 ubuntu:$UBUNTU_VERSION AS runner
ARG MUSL_TOOLCHAIN

# Configure APT and DPKG for multiarch and package caching
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache && \
    dpkg --add-architecture armhf

# Install base packages (including arm32 libraries and headers)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        make \
        pkg-config \
        binutils-arm-linux-gnueabihf \
        gcc-arm-linux-gnueabihf \
        python3-minimal \
        python3-pip \
        python3-venv \
        libpython3-dev \
        libpython3-dev:armhf \
        ninja-build \
        bash

# Add musl toolchain
COPY --from=musl-toolchain-downloader --link /$MUSL_TOOLCHAIN /opt/$MUSL_TOOLCHAIN
ENV PATH=$PATH:/opt/$MUSL_TOOLCHAIN/bin

# Add Python venv => set up in different container for better caching
COPY --from=python-builder --link /root/.venv /root/.venv

COPY --from=aflplusplus/aflplusplus@sha256:db5756f9351150c2ffbab9cbb5a92d8048b8d79f8f023e9d614db2e93372c005 --link /usr/local/bin /opt/afl
ENV PATH=$PATH:/opt/afl

# Copy entrypoint in
COPY --link --chmod=0755 docker/runner-entrypoint.sh /runner-entrypoint.sh

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/runner-entrypoint.sh"]


################################################################################
# Download and decompress ghidra(thon) for use in the final ghidrathon image   #
################################################################################
FROM alpine:latest AS ghidra-ghidrathon-downloader
ARG GHIDRA_VERSION
ARG GHIDRA_SHA
ARG GHIDRA_URL
ARG GHIDRATHON_SHA
ARG GHIDRATHON_URL

# Download and decompress ghidra because ADD cannot (yet) do both at once
ADD --link $GHIDRA_URL /ghidra.zip

RUN echo "$GHIDRA_SHA  /ghidra.zip" | sha256sum -c - && \
    unzip /ghidra.zip && \
    mv ghidra_${GHIDRA_VERSION} /ghidra && \
    chmod +x /ghidra/ghidraRun

# Download and decompress ghidrathon because ADD cannot (yet) do both at once
ADD --link $GHIDRATHON_URL /ghidrathon.zip

RUN echo "$GHIDRATHON_SHA  /ghidrathon.zip" | sha256sum -c - && \
    unzip /ghidrathon.zip -d /ghidrathon && \
    rm /ghidrathon.zip


################################################################################
# Ghidrathon image                                                             #
################################################################################
FROM ubuntu:$UBUNTU_VERSION AS ghidrathon
ARG GHIDRA_VERSION

# Enable APT package caching
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install prerequisites
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        vim \
        wget \
        unzip \
        build-essential \
        libssl-dev \
        libffi-dev \
        python3-dev \
        python3-requests  \
        python3-ipdb \
        python3-venv \
        python3-pip \
        python-is-python3 \
        apt-transport-https \
        software-properties-common \
        gpg-agent \
        dirmngr \
        openjdk-21-jdk-headless \
        git

# Setup JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

# Install Python dependencies
RUN --mount=type=bind,source=src/ghidrathon/requirements.txt,target=/requirements.txt \
    --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    pip3 install --break-system-packages -r /requirements.txt

# Add ghidra
COPY --from=ghidra-ghidrathon-downloader --link /ghidra /ghidra

# Add ghidrathon
COPY --from=ghidra-ghidrathon-downloader --link /ghidrathon /ghidrathon

RUN cd /ghidrathon && \
    pip3 install --break-system-packages -r requirements.txt && \
    python3 ghidrathon_configure.py /ghidra && \
    mkdir -p ~/.ghidra/.ghidra_${GHIDRA_VERSION}/Extensions && \
    cp -r /ghidrathon ~/.ghidra/.ghidra_${GHIDRA_VERSION}/Extensions/Ghidrathon

# Setup pyghidraRun for python usage
RUN python -m venv ~/.config/ghidra/ghidra_${GHIDRA_VERSION}/venv && \
    ~/.config/ghidra/ghidra_${GHIDRA_VERSION}/venv/bin/python3 -m pip install -r /ghidrathon/requirements.txt && \
    ~/.config/ghidra/ghidra_${GHIDRA_VERSION}/venv/bin/python3 -m pip install pyyaml && \
    ~/.config/ghidra/ghidra_${GHIDRA_VERSION}/venv/bin/python3 /ghidrathon/ghidrathon_configure.py /ghidra

# Copy entrypoint in
COPY --link --chmod=0755 docker/ghidrathon-entrypoint.sh /ghidrathon-entrypoint.sh

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["/ghidrathon-entrypoint.sh"]
