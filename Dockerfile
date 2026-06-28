# Pinned base image (by digest) for reproducible, tamper-evident builds.
FROM alpine:3.22@sha256:14358309a308569c32bdc37e2e0e9694be33a9d99e68afb0f5ff33cc1f695dce

# Runtime deps: Python + pip, ffmpeg (muxing), node (JS challenge solving),
# tzdata/ca-certificates. curl_cffi (installed below) needs no build toolchain —
# it ships prebuilt musllinux wheels.
RUN apk add --no-cache \
    python3 \
    py3-pip \
    ffmpeg \
    tzdata \
    ca-certificates \
    nodejs

# Install yt-dlp, the bgutil PO-token plugin, and curl_cffi from PyPI, all
# version-pinned. Installing via pip (rather than the standalone binary) is what
# lets yt-dlp load curl_cffi for browser-TLS impersonation and auto-discover the
# plugin — both are plain site-packages. The base image stays digest-pinned for
# reproducibility; pin the package versions here to control what ships.
ARG YTDLP_VERSION=2026.06.09
ARG POT_PLUGIN_VERSION=1.3.1
ARG CURL_CFFI_VERSION=0.15.0
RUN pip install --break-system-packages --no-cache-dir \
        "yt-dlp[default]==${YTDLP_VERSION}" \
        "bgutil-ytdlp-pot-provider==${POT_PLUGIN_VERSION}" \
        "curl_cffi==${CURL_CFFI_VERSION}"

# Run as an unprivileged user; only /downloads is writable (and it is bind-mounted at runtime).
RUN adduser -D -u 1000 safe-exec && \
    mkdir -p /downloads && chown safe-exec:safe-exec /downloads

USER safe-exec
WORKDIR /downloads

ENTRYPOINT ["yt-dlp"]

CMD ["--help"]
