#!/bin/bash

# Shared helpers for the yt-dlp wrapper scripts.
# Keeps interactive prompts, cookie handling, image build and the hardened
# `docker run` invocation in ONE place, so the security flags can't drift
# between scripts. Sourced by the download_*.sh wrappers.

# Always operate from the project root, no matter where the script was invoked
# from (downloads/ and `docker build .` are resolved relative to it).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

IMAGE="isolated-yt-dlp"
COOKIE_FILE="downloads/cookies.txt"

mkdir -p downloads

# Return $1, or interactively prompt for it when empty.
# Usage: URL=$(prompt_if_empty "$1" "Video URL")
prompt_if_empty() {
    local value="$1" label="$2"
    if [ -z "$value" ]; then
        printf '%s: ' "$label" >&2   # prompt on stderr so stdout stays the value
        read -r value
    fi
    printf '%s' "$value"
}

# Populate the global COOKIE_ARGS array. Uses downloads/cookies.txt if present,
# otherwise asks (interactive terminals only) for a path and copies it in — so
# the user never has to remember the --cookies flag.
resolve_cookies() {
    COOKIE_ARGS=()
    if [ -f "$COOKIE_FILE" ]; then
        COOKIE_ARGS=(--cookies "/downloads/cookies.txt")
        echo "Using cookies: $COOKIE_FILE"
        return
    fi
    [ -t 0 ] || return   # don't block on prompts when run non-interactively
    printf 'Path to a cookies.txt (Enter to skip, needed only if YouTube asks to "confirm you are not a bot"): ' >&2
    local path
    read -r path
    if [ -n "$path" ] && [ -f "$path" ]; then
        cp "$path" "$COOKIE_FILE"
        COOKIE_ARGS=(--cookies "/downloads/cookies.txt")
        echo "Using cookies: $path"
    fi
}

# Build the container image quietly.
build_image() {
    docker build -q -t "$IMAGE" . > /dev/null
}

# Run yt-dlp inside the hardened container. All arguments are passed to yt-dlp.
# This is the single source of truth for the isolation flags.
run_ytdlp() {
    docker run --rm -i \
        --cap-drop=ALL \
        --security-opt=no-new-privileges:true \
        --read-only \
        --tmpfs /tmp:rw,size=512m \
        --memory=1g \
        --pids-limit=512 \
        -v "$(pwd)/downloads:/downloads" \
        "$IMAGE" "$@"
}
