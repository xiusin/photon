# PhotonBlog Demo — Multi-stage Dockerfile
#
# Build context must be the parent directory (photon root) so that both
# the Photon framework source and the Demo project are available:
#
#   docker build -t photonblog -f Demo/Dockerfile .

# ── Stage 1: Builder ──
FROM ubuntu:22.04 AS builder

ARG V_BRANCH=weekly.2025.06

RUN apt-get update && apt-get install -y --no-install-recommends \
    git make gcc libc6-dev ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Install V compiler
RUN git clone --depth 1 --branch ${V_BRANCH} https://github.com/vlang/v.git /tmp/v && \
    cd /tmp/v && make && /tmp/v/v symlink

# Copy Photon framework + Demo project
COPY . /app

WORKDIR /app/Demo

# Compile the PhotonBlog binary
RUN v -enable-globals -o demo . && \
    ls -lh demo

# ── Stage 2: Runtime ──
FROM ubuntu:22.04

LABEL org.opencontainers.image.title="PhotonBlog"
LABEL org.opencontainers.image.description="A complete blog/CMS demo built with Photon Framework"
LABEL org.opencontainers.image.vendor="Photon Framework"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd -r photonblog && useradd -r -g photonblog photonblog && \
    mkdir -p /opt/photonblog/storage/uploads /opt/photonblog/logs && \
    chown -R photonblog:photonblog /opt/photonblog

COPY --from=builder /app/Demo/demo /opt/photonblog/app

WORKDIR /opt/photonblog
USER photonblog

ENV APP_PROFILE=prod
ENV APP_SERVER_HOST=0.0.0.0
ENV APP_SERVER_PORT=8080
ENV APP_DEBUG=false

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

CMD ["/opt/photonblog/app", "serve"]
