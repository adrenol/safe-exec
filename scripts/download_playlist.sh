#!/bin/bash

# Script for downloading an entire playlist via yt-dlp

URL=$1
shift

if [ -z "$URL" ]; then
    echo "Usage: bash download_playlist.sh <PLAYLIST_URL> [additional_yt_dlp_arguments]"
    exit 1
fi

mkdir -p downloads

docker build -q -t isolated-yt-dlp . > /dev/null

echo "Starting playlist download: $URL"

# Run the container.
# -i (ignore-errors) allows the download to continue if a video is unavailable.
# -o "%(playlist_index)s - %(title)s.%(ext)s" saves files with their playlist index number.
# --yes-playlist confirms that we are downloading a playlist.
docker run --rm -i \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    -v "$(pwd)/downloads:/downloads" \
    isolated-yt-dlp \
    -i \
    -o "%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s" \
    --yes-playlist \
    --js-runtimes node \
    "$URL" "$@"
