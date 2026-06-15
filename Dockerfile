# Photon Framework — Production Dockerfile
# Multi-stage build: V compiler → binary → minimal runtime image

# ── Stage 1: Build ──
FROM ubuntu:22.04 AS builder

ARG V_BRANCH=weekly.2025.06

RUN apt-get update && apt-get install -y --no-install-recommends \
    git make gcc libc6-dev ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Install V compiler
RUN git clone --depth 1 --branch ${V_BRANCH} https://github.com/vlang/v.git /tmp/v && \
    cd /tmp/v && make && /tmp/v/v symlink

# Build Photon application
COPY . /app
WORKDIR /app/photon
RUN mkdir -p bin && \
    v -enable-globals -prod -o bin/photon example/main.v && \
    ls -lh bin/

# ── Stage 2: Runtime ──
FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Photon Framework"
LABEL org.opencontainers.image.description="A Spring-like application framework for V language"
LABEL org.opencontainers.image.url="https://github.com/xiusin/photon"
LABEL org.opencontainers.image.vendor="Photon Framework"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -r photon && useradd -r -g photon photon && \
    mkdir -p /opt/photon/data /opt/photon/logs && \
    chown -R photon:photon /opt/photon

COPY --from=builder /app/photon/bin/photon /opt/photon/app
COPY --from=builder /app/photon/systemd/photon.service /opt/photon/

WORKDIR /opt/photon
USER photon

ENV APP_ENV=production
ENV APP_HOST=0.0.0.0
ENV APP_PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/opt/photon/app"]
