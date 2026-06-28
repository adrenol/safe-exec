# Pinned base image (by digest) for reproducible, tamper-evident builds.
FROM alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce

# Runtime deps. curl is only needed to fetch yt-dlp, so it is removed afterwards
# to keep it out of the final image's attack surface.
RUN apk add --no-cache \
    python3 \
    ffmpeg \
    tzdata \
    ca-certificates \
    nodejs

# Install a pinned yt-dlp release and verify its SHA256 before trusting it.
# This is the key supply-chain control: a tampered binary fails the checksum
# and aborts the build instead of ending up runnable in the image.
ARG YTDLP_VERSION=2026.06.09
ARG YTDLP_SHA256=e5d57466682cfa9d61e9cf7c8a4f09b00f4a62af37d3bbdc4bcffdf63615feac
RUN apk add --no-cache --virtual .fetch curl && \
    curl -fL "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp" \
        -o /usr/local/bin/yt-dlp && \
    echo "${YTDLP_SHA256}  /usr/local/bin/yt-dlp" | sha256sum -c - && \
    chmod a+rx /usr/local/bin/yt-dlp && \
    apk del .fetch

# Run as an unprivileged user; only /downloads is writable (and it is bind-mounted at runtime).
RUN adduser -D -u 1000 safe-exec && \
    mkdir -p /downloads && chown safe-exec:safe-exec /downloads

USER safe-exec
WORKDIR /downloads

ENTRYPOINT ["yt-dlp"]

CMD ["--help"]
