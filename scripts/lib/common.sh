#!/bin/bash

# Shared helpers for the yt-dlp wrapper scripts.
# Keeps interactive prompts, cookie/proxy handling, image build and the hardened
# `docker run` invocation in ONE place, so the security flags can't drift
# between scripts. Sourced by the download_*.sh wrappers.

# Always operate from the project root, no matter where the script was invoked
# from (downloads/ and `docker build .` are resolved relative to it).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

IMAGE="isolated-yt-dlp"
COOKIE_FILE="downloads/cookies.txt"
PROXY_FILE="proxies.txt"

# PO-token provider (bgutil): pinned by digest, run in its own hardened container
# on a dedicated network. Used as a fallback when YouTube shows the "confirm
# you're not a bot" gate and a clean IP / cookies aren't enough on their own.
POT_IMAGE="brainicism/bgutil-ytdlp-pot-provider@sha256:1aaa43a0ca72dfca6a6d2129a0fb4a23465c25adb1b043f8aff829a20825646b"
POT_NAME="safe-exec-pot-provider"
POT_NETWORK="safe-exec-pot-net"
POT_BASEURL="http://${POT_NAME}:4416"

PROXY_ARGS=()   # current --proxy args injected into each run_ytdlp call
PROXY_LIST=()   # all proxies from proxies.txt, as yt-dlp proxy URLs

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

# Populate the global COOKIE_ARGS array from downloads/cookies.txt if it exists.
# Cookies are optional now (proxy rotation + impersonation + PO token usually
# suffice), so this never prompts — drop a cookies.txt in only if you want it.
resolve_cookies() {
    COOKIE_ARGS=()
    if [ -f "$COOKIE_FILE" ]; then
        COOKIE_ARGS=(--cookies "/downloads/cookies.txt")
        echo "Using cookies: $COOKIE_FILE"
    fi
}

# Convert one proxy line into a yt-dlp proxy URL. Accepts:
#   scheme://...            -> used as-is
#   host:port:user:pass     -> http://user:pass@host:port  (common provider format)
#   host:port               -> http://host:port
to_proxy_url() {
    local p="$1"
    case "$p" in
        *://*) printf '%s' "$p"; return ;;
    esac
    local IFS=:
    set -- $p
    if [ "$#" -ge 4 ]; then
        printf 'http://%s:%s@%s:%s' "$3" "$4" "$1" "$2"
    elif [ "$#" -eq 2 ]; then
        printf 'http://%s:%s' "$1" "$2"
    fi
}

# Load proxies.txt (skipping blanks/comments) into the PROXY_LIST array.
load_proxies() {
    PROXY_LIST=()
    [ -f "$PROXY_FILE" ] || return
    local line url
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//[$' \t\r']/}"
        [ -z "$line" ] && continue
        case "$line" in '#'*) continue ;; esac
        url="$(to_proxy_url "$line")"
        [ -n "$url" ] && PROXY_LIST+=("$url")
    done < "$PROXY_FILE"
    [ "${#PROXY_LIST[@]}" -gt 0 ] && echo "Loaded ${#PROXY_LIST[@]} proxies from $PROXY_FILE"
}

# Hide credentials when printing a proxy URL.
mask_proxy() { printf '%s' "$1" | sed -E 's#://[^@/]*@#://***@#'; }

# Build the container image quietly.
build_image() {
    docker build -q -t "$IMAGE" . > /dev/null
}

# Run yt-dlp inside the hardened container. All arguments are passed to yt-dlp.
# This is the single source of truth for the isolation flags. Set DOCKER_NET to
# attach the run to a specific network (used for the PO-token provider).
run_ytdlp() {
    local net=()
    [ -n "${DOCKER_NET:-}" ] && net=(--network "$DOCKER_NET")
    docker run --rm -i \
        --cap-drop=ALL \
        --security-opt=no-new-privileges:true \
        --read-only \
        --tmpfs /tmp:rw,size=512m \
        --memory=1g \
        --pids-limit=512 \
        "${net[@]}" \
        -v "$(pwd)/downloads:/downloads" \
        "$IMAGE" --impersonate chrome "${PROXY_ARGS[@]}" "$@"
}

# Start the PO-token provider (if not already up) on its own network and wait
# until its port answers. Needs outbound internet to mint tokens, but is still
# locked down: all caps dropped, no privilege escalation, RAM/PID capped, and
# reachable only from our network. Routed through the same proxy when set.
ensure_pot_provider() {
    docker network inspect "$POT_NETWORK" >/dev/null 2>&1 || \
        docker network create "$POT_NETWORK" >/dev/null
    if ! docker ps --format '{{.Names}}' | grep -qx "$POT_NAME"; then
        echo "Starting isolated PO-token provider..."
        local proxy_env=()
        if [ "${#PROXY_ARGS[@]}" -ge 2 ]; then
            proxy_env=(-e "HTTP_PROXY=${PROXY_ARGS[1]}" -e "HTTPS_PROXY=${PROXY_ARGS[1]}")
        fi
        docker run -d --rm --init \
            --name "$POT_NAME" \
            --network "$POT_NETWORK" \
            --cap-drop=ALL \
            --security-opt=no-new-privileges:true \
            --memory=512m \
            --pids-limit=256 \
            "${proxy_env[@]}" \
            "$POT_IMAGE" >/dev/null
    fi
    # Poll the provider port from a throwaway container on the same network
    # (uses the python3 already in our image — no curl needed).
    local i
    for i in $(seq 1 30); do
        if docker run --rm --network "$POT_NETWORK" --entrypoint python3 "$IMAGE" \
            -c "import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(('${POT_NAME}',4416))==0 else 1)" \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "PO-token provider did not become ready in time." >&2
    return 1
}

# Tear down the provider container and its network.
stop_pot_provider() {
    docker rm -f "$POT_NAME" >/dev/null 2>&1
    docker network rm "$POT_NETWORK" >/dev/null 2>&1
}

# One yt-dlp attempt. Returns 0 only if it exits cleanly AND YouTube didn't show
# the bot gate; otherwise 1 (so the caller can try another proxy / escalate).
_attempt() {
    local log rc
    log="$(mktemp)"
    run_ytdlp "$@" 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    if [ "$rc" -eq 0 ] && ! grep -qiE "sign in to confirm|not a bot" "$log"; then
        rm -f "$log"; return 0
    fi
    rm -f "$log"; return 1
}

# Last resort: bring up the isolated PO-token provider and retry once, forcing a
# web client so yt-dlp actually requests a token. Uses whatever PROXY_ARGS is set.
_escalate_pot() {
    echo
    echo "Bringing up isolated PO-token provider and retrying..."
    ensure_pot_provider || return 1
    trap stop_pot_provider EXIT
    DOCKER_NET="$POT_NETWORK" run_ytdlp \
        --extractor-args "youtubepot-bgutilhttp:base_url=${POT_BASEURL}" \
        --extractor-args "youtube:player_client=web,default" "$@"
}

# Main entry point used by the wrappers:
#  - no proxies: one direct attempt, PO-token fallback on the bot gate;
#  - with proxies: try several in random order until one downloads cleanly,
#    then fall back to a PO token over the first proxy if all are blocked.
run_ytdlp_auto() {
    # Don't probe the (unstarted) PO provider on normal runs — it only adds a
    # noisy warning. The provider is brought up explicitly during escalation.
    local no_pot=(--extractor-args "youtube:fetch_pot=never")

    if [ "${#PROXY_LIST[@]}" -eq 0 ]; then
        _attempt "${no_pot[@]}" "$@" && return 0
        _escalate_pot "$@"
        return
    fi

    local order idx tried=0 max=8
    order="$(seq 0 $(( ${#PROXY_LIST[@]} - 1 )) | awk 'BEGIN{srand()}{print rand()"\t"$0}' | sort -k1,1n | cut -f2)"
    for idx in $order; do
        tried=$((tried + 1))
        [ "$tried" -gt "$max" ] && break
        PROXY_ARGS=(--proxy "${PROXY_LIST[$idx]}" --socket-timeout 20)
        echo "[proxy $tried] via $(mask_proxy "${PROXY_LIST[$idx]}")"
        _attempt "${no_pot[@]}" "$@" && return 0
        echo "  -> failed/blocked, trying next proxy"
    done

    echo "All tried proxies blocked; escalating to PO token over the first proxy..."
    PROXY_ARGS=(--proxy "${PROXY_LIST[$(printf '%s\n' $order | head -n1)]}")
    _escalate_pot "$@"
}

load_proxies
