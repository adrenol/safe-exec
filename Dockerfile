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

# Install yt-dlp, the bgutil PO-token plugin and curl_cffi (browser-TLS
# impersonation) from a fully hash-pinned lockfile. --require-hashes makes pip
# refuse any package — direct or transitive — whose artifact doesn't match a
# recorded SHA256, so the build aborts on tampered or substituted dependencies.
# Regenerate requirements.txt from requirements.in (see header in that file).
# Installing via pip (rather than the standalone binary) is what lets yt-dlp
# load curl_cffi and auto-discover the plugin — both are plain site-packages.
COPY requirements.txt .
RUN pip install --break-system-packages --no-cache-dir \
        --require-hashes -r requirements.txt && \
    rm requirements.txt

# Run as an unprivileged user; only /downloads is writable (and it is bind-mounted at runtime).
RUN adduser -D -u 1000 safe-exec && \
    mkdir -p /downloads && chown safe-exec:safe-exec /downloads

USER safe-exec
WORKDIR /downloads

ENTRYPOINT ["yt-dlp"]

CMD ["--help"]
