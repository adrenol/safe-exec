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

# yt-dlp looks for plugins under $XDG_CONFIG_HOME/yt-dlp/plugins. Baking them into
# a system path (not the user's home) keeps them readable under a --read-only root.
ENV XDG_CONFIG_HOME=/etc/xdg

# Install pinned, checksum-verified yt-dlp and the bgutil PO-token plugin.
# Both downloads abort the build on a checksum mismatch instead of shipping a
# tampered artifact. The plugin only speaks HTTP to the separate provider
# container, so no extra runtime deps land here.
ARG YTDLP_VERSION=2026.06.09
ARG YTDLP_SHA256=e5d57466682cfa9d61e9cf7c8a4f09b00f4a62af37d3bbdc4bcffdf63615feac
ARG POT_PLUGIN_VERSION=1.3.1
ARG POT_PLUGIN_SHA256=b8ceec7f76143da172aaf5ebeec0c2d218e5680c063b931586bca48567069b38
RUN apk add --no-cache --virtual .fetch curl && \
    curl -fL "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp" \
        -o /usr/local/bin/yt-dlp && \
    echo "${YTDLP_SHA256}  /usr/local/bin/yt-dlp" | sha256sum -c - && \
    chmod a+rx /usr/local/bin/yt-dlp && \
    curl -fL "https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/${POT_PLUGIN_VERSION}/bgutil-ytdlp-pot-provider.zip" \
        -o /tmp/pot.zip && \
    echo "${POT_PLUGIN_SHA256}  /tmp/pot.zip" | sha256sum -c - && \
    mkdir -p "${XDG_CONFIG_HOME}/yt-dlp/plugins/bgutil-pot" && \
    python3 -m zipfile -e /tmp/pot.zip "${XDG_CONFIG_HOME}/yt-dlp/plugins/bgutil-pot/" && \
    rm /tmp/pot.zip && \
    apk del .fetch

# Run as an unprivileged user; only /downloads is writable (and it is bind-mounted at runtime).
RUN adduser -D -u 1000 safe-exec && \
    mkdir -p /downloads && chown safe-exec:safe-exec /downloads

USER safe-exec
WORKDIR /downloads

ENTRYPOINT ["yt-dlp"]

CMD ["--help"]
