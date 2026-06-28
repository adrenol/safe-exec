#!/bin/bash

# Download an entire playlist via yt-dlp in a hardened container.
# Run with no arguments to be prompted for the URL interactively, or pass it:
#   bash download_playlist.sh <PLAYLIST_URL> [extra yt-dlp args]

source "$(dirname "$0")/lib/common.sh"

URL=$(prompt_if_empty "$1" "Playlist URL")
[ "$#" -gt 0 ] && shift

if [ -z "$URL" ]; then
    echo "No URL provided."
    exit 1
fi

build_image
resolve_cookies

echo "Starting playlist download: $URL"

# -i                : keep going if a single video is unavailable.
# -o "<title>/..."  : group files under a per-playlist folder, numbered.
# --yes-playlist    : treat the URL as a playlist.
run_ytdlp_auto \
    -i \
    -o "%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s" \
    --yes-playlist \
    --js-runtimes node \
    --no-cache-dir \
    "${COOKIE_ARGS[@]}" \
    "$URL" "$@"
