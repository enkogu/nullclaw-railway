# syntax=docker/dockerfile:1

FROM alpine:3.23 AS builder

ARG NULLCLAW_REPO="https://github.com/nullclaw/nullclaw.git"
ARG NULLCLAW_REF="4101f63"

RUN apk add --no-cache git zig musl-dev

WORKDIR /src
COPY patches /tmp/patches
RUN git clone "${NULLCLAW_REPO}" nullclaw \
    && git -C /src/nullclaw checkout "${NULLCLAW_REF}"
RUN git -C /src/nullclaw apply /tmp/patches/0001-subagent-wakeup.patch

WORKDIR /src/nullclaw
ARG TARGETARCH
RUN set -eu; \
    arch="${TARGETARCH:-}"; \
    if [ -z "${arch}" ]; then \
      case "$(uname -m)" in \
        x86_64) arch="amd64" ;; \
        aarch64|arm64) arch="arm64" ;; \
        *) echo "Unsupported host arch: $(uname -m)" >&2; exit 1 ;; \
      esac; \
    fi; \
    case "${arch}" in \
      amd64) zig_target="x86_64-linux-musl" ;; \
      arm64) zig_target="aarch64-linux-musl" ;; \
      *) echo "Unsupported TARGETARCH: ${arch}" >&2; exit 1 ;; \
    esac; \
    zig build -Dtarget="${zig_target}" -Doptimize=ReleaseSmall

FROM golang:1.26-alpine AS pinchtab-builder

ARG PINCHTAB_REPO="https://github.com/pinchtab/pinchtab.git"
ARG PINCHTAB_REF="30394d37c70095b4c8cae4d3b528de5793ba4338"

RUN apk add --no-cache git
WORKDIR /src
RUN git clone "${PINCHTAB_REPO}" pinchtab \
    && git -C /src/pinchtab checkout "${PINCHTAB_REF}"
WORKDIR /src/pinchtab
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/pinchtab ./cmd/pinchtab

FROM alpine:3.23 AS runtime

RUN apk add --no-cache \
    ca-certificates tzdata curl git bash ripgrep jq \
    chromium nss freetype harfbuzz ttf-freefont \
    xvfb x11vnc novnc websockify

RUN addgroup -S app && adduser -S -G app app

COPY --from=builder /src/nullclaw/zig-out/bin/nullclaw /usr/local/bin/nullclaw
COPY --from=pinchtab-builder /out/pinchtab /usr/local/bin/pinchtab
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY scripts/pinchtab-client.sh /usr/local/bin/pinchtab-client.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/pinchtab-client.sh /usr/local/bin/pinchtab \
    && mkdir -p /data/.nullclaw/workspace \
    && chown -R app:app /data

ENV HOME=/data
ENV NULLCLAW_HOME=/data
ENV NULLCLAW_WORKSPACE=/data/.nullclaw/workspace
ENV PORT=3000

WORKDIR /data
EXPOSE 3000 9867 5900 6080
USER app

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
