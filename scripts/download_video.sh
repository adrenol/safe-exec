#!/bin/bash

# Download a single video via yt-dlp in a hardened container.
# Run with no arguments to be prompted for the URL interactively, or pass it:
#   bash download_video.sh <VIDEO_URL> [extra yt-dlp args]

source "$(dirname "$0")/lib/common.sh"

URL=$(prompt_if_empty "$1" "Video URL")
[ "$#" -gt 0 ] && shift

if [ -z "$URL" ]; then
    echo "No URL provided."
    exit 1
fi

build_image
resolve_cookies

echo "Starting download: $URL"
run_ytdlp_auto --js-runtimes node --no-cache-dir "${COOKIE_ARGS[@]}" "$URL" "$@"
