#!/bin/bash

# Wrapper script for convenient yt-dlp execution via Docker

URL=$1
shift

if [ -z "$URL" ]; then
    echo "Usage: ./download.sh <VIDEO_URL> [additional_yt_dlp_arguments]"
    exit 1
fi

# Create downloads directory if it doesn't exist
mkdir -p downloads

# Build the image if not already built (silently)
docker build -q -t isolated-yt-dlp . > /dev/null

echo "Starting download: $URL"

# Run the container.
# The --rm flag removes the container after completion.
# -v $(pwd)/downloads:/downloads mounts the directory.
docker run --rm -i \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    -v "$(pwd)/downloads:/downloads" \
    isolated-yt-dlp --js-runtimes node "$URL" "$@"
