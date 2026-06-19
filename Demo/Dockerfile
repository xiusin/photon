# PhotonBlog Demo — Multi-stage Dockerfile
#
# Build context must be the parent directory (photon root) so that both
# the Photon framework source and the Demo project are available:
#
#   docker build -t photonblog -f Demo/Dockerfile .
#
# 多架构构建：
#   docker buildx build --platform linux/amd64,linux/arm64 -t photonblog -f Demo/Dockerfile .

# ── Stage 1: Builder ──
FROM ubuntu:22.04 AS builder

ARG V_BRANCH=weekly.2025.06
ARG TARGETPLATFORM

RUN apt-get update && apt-get install -y --no-install-recommends \
    git make gcc libc6-dev ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Install V compiler
RUN git clone --depth 1 --branch ${V_BRANCH} https://github.com/vlang/v.git /tmp/v && \
    cd /tmp/v && make && /tmp/v/v symlink

# Copy Photon framework + Demo project
COPY . /app

WORKDIR /app/Demo

# Compile the PhotonBlog binary (release optimized)
RUN v -enable-globals -d release -cflags "-O2" -o demo . && \
    ls -lh demo

# ── Stage 2: Runtime (minimal) ──
FROM alpine:3.18

LABEL org.opencontainers.image.title="PhotonBlog"
LABEL org.opencontainers.image.description="A complete blog/CMS demo built with Photon Framework"
LABEL org.opencontainers.image.vendor="Photon Framework"
LABEL org.opencontainers.image.licenses="MIT"

# Install minimal runtime dependencies (curl for healthcheck, wget as fallback)
RUN apk add --no-cache ca-certificates curl wget tzdata && \
    addgroup -S photonblog && adduser -S -G photonblog photonblog && \
    mkdir -p /app/storage/uploads /app/storage/logs /app/config /app/database/migrations /app/database/seeders && \
    chown -R photonblog:photonblog /app

# Copy binary from builder
COPY --from=builder /app/Demo/demo /app/demo

# Copy config templates and migrations (for fresh deployments)
COPY --from=builder /app/Demo/.env.example /app/.env.example
COPY --from=builder /app/Demo/config/ /app/config/
COPY --from=builder /app/Demo/database/migrations/ /app/database/migrations/
COPY --from=builder /app/Demo/database/seeders/ /app/database/seeders/

WORKDIR /app
USER photonblog

# Default environment
ENV APP_PROFILE=prod
ENV APP_SERVER_HOST=0.0.0.0
ENV APP_SERVER_PORT=8080
ENV APP_DEBUG=false
ENV DB_PATH=/app/storage/photonblog.db
ENV LOG_CHANNEL=file
ENV LOG_FILE_PATH=/app/storage/logs/app.log
ENV LOG_JSON_FORMAT=true

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/health || exit 1

CMD ["/app/demo", "serve"]
