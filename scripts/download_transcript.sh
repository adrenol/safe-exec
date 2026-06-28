#!/bin/bash

# Extract a transcript (subtitles) from a YouTube video via yt-dlp, then strip
# timestamps to produce a clean plain-text transcript in downloads/.
# Run with no arguments to be prompted, or pass them:
#   bash download_transcript.sh <VIDEO_URL> [LANGS] [extra yt-dlp args]

source "$(dirname "$0")/lib/common.sh"

URL=$(prompt_if_empty "$1" "Video URL")
[ "$#" -gt 0 ] && shift
LANGS=$(prompt_if_empty "${1:-en,ru}" "Subtitle languages (comma-separated)")
[ "$#" -gt 0 ] && shift

if [ -z "$URL" ]; then
    echo "No URL provided."
    exit 1
fi

build_image
resolve_cookies

echo "Fetching transcript: $URL (langs: $LANGS)"

# --skip-download    : we only want subtitles, not the video.
# --write-subs       : grab human-made subtitles when available.
# --write-auto-subs  : fall back to YouTube's auto-generated captions.
# --convert-subs srt : normalize whatever format YouTube returns into .srt.
# --no-cache-dir     : don't write to the (read-only) home cache directory.
run_ytdlp \
    --skip-download \
    --write-subs \
    --write-auto-subs \
    --sub-langs "$LANGS" \
    --convert-subs srt \
    --no-cache-dir \
    -o "%(title)s.%(ext)s" \
    --js-runtimes node \
    "${COOKIE_ARGS[@]}" \
    "$URL" "$@"

# Convert every .srt into a clean .txt transcript (no indices, timestamps or
# tags). Runs INSIDE a hardened container (with networking disabled) so the
# untrusted subtitle files are never processed in the host shell.
echo "Converting subtitles to plain text..."
docker run --rm -i \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    --network=none \
    --read-only \
    --tmpfs /tmp:rw,size=16m \
    --memory=128m \
    --pids-limit=64 \
    -v "$(pwd)/downloads:/downloads" \
    --entrypoint sh \
    "$IMAGE" -c '
        for srt in /downloads/*.srt; do
            [ -e "$srt" ] || continue
            txt="${srt%.srt}.txt"
            awk "
                /-->/      { next }              # timestamp lines
                /^[0-9]+\$/ { next }             # subtitle index lines
                /^[[:space:]]*\$/ { next }       # blank lines
                {
                    gsub(/<[^>]*>/, \"\")        # strip inline tags
                    if (\$0 != prev) { print; prev = \$0 }   # drop consecutive duplicates
                }
            " "$srt" > "$txt"
            echo "  -> $txt"
        done
    '
