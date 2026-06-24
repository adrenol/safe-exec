FROM alpine:latest

RUN apk add --no-cache \
    python3 \
    ffmpeg \
    tzdata \
    ca-certificates \
    curl \
    nodejs

RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && \
    chmod a+rx /usr/local/bin/yt-dlp

RUN adduser -D -u 1000 safe-exec

RUN mkdir -p /downloads && chown safe-exec:safe-exec /downloads

USER safe-exec
WORKDIR /downloads

ENTRYPOINT ["yt-dlp"]

CMD ["--help"]