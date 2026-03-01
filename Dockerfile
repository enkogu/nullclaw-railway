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

FROM alpine:3.23 AS runtime

RUN apk add --no-cache \
    ca-certificates tzdata curl git bash ripgrep nodejs npm \
    chromium nss freetype harfbuzz ttf-freefont
RUN addgroup -S app && adduser -S -G app app

COPY --from=builder /src/nullclaw/zig-out/bin/nullclaw /usr/local/bin/nullclaw
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && mkdir -p /data/.nullclaw/workspace \
    && chown -R app:app /data

ENV HOME=/data
ENV NULLCLAW_HOME=/data
ENV NULLCLAW_WORKSPACE=/data/.nullclaw/workspace
ENV PORT=3000

WORKDIR /data
EXPOSE 3000
USER app

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
