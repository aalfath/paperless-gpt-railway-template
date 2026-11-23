#!/bin/sh
# Start script for paperless-gpt on Railway.
# - keeps prompts, settings, workflows and the undo/OCR history on the volume
# - runs paperless-gpt on 127.0.0.1:8081 (it has no login of its own)
# - runs Caddy on $PORT with HTTP basic auth and an open /healthz
# - sizes Go and page-rendering limits to the service's memory
# - exits non-zero as soon as either process stops, so Railway restarts it
set -eu

DATA_DIR="${DATA_DIR:-/data}"
PORT="${PORT:-8080}"
APP_PORT=8081
PUID="${PUID:-10001}"
PGID="${PGID:-10001}"
export ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"

log() { echo "[start] $*"; }
die() { echo "[start] ERROR: $*" >&2; exit 1; }

[ "$PORT" != "$APP_PORT" ] || die "PORT must not be $APP_PORT (used internally by paperless-gpt)."
[ -n "${ADMIN_PASSWORD:-}" ] || die "ADMIN_PASSWORD is empty. Set it in the service variables."
[ "${#ADMIN_PASSWORD}" -ge 12 ] || die "ADMIN_PASSWORD must be at least 12 characters."
[ -n "${PAPERLESS_BASE_URL:-}" ] || die "PAPERLESS_BASE_URL is empty. Set it to the address of your Paperless-ngx, e.g. https://paperless.YOUR-DOMAIN."
case "$PAPERLESS_BASE_URL" in
  http://*|https://*) ;;
  *) log "PAPERLESS_BASE_URL has no scheme; using https://$PAPERLESS_BASE_URL"; PAPERLESS_BASE_URL="https://$PAPERLESS_BASE_URL" ;;
esac
PAPERLESS_BASE_URL="${PAPERLESS_BASE_URL%/}"
export PAPERLESS_BASE_URL
[ -n "${PAPERLESS_API_TOKEN:-}" ] || die "PAPERLESS_API_TOKEN is empty. Create one in Paperless-ngx under My Profile > API Auth Token."

# LLM defaults: any OpenAI-compatible API. Other upstream providers (anthropic,
# googleai, mistral, ollama) work by setting LLM_PROVIDER and their own key.
export LLM_PROVIDER="${LLM_PROVIDER:-openai}"
export LLM_MODEL="${LLM_MODEL:-gpt-5-mini}"
if [ "$LLM_PROVIDER" = openai ]; then
  [ -n "${OPENAI_API_KEY:-}" ] || die "OPENAI_API_KEY is empty. Add your OpenAI (or OpenAI-compatible) API key in the service variables."
  export OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
fi
# Vision OCR uses the same provider and model unless set otherwise.
# Set VISION_LLM_PROVIDER to "none" to turn LLM OCR off.
if [ "${VISION_LLM_PROVIDER:-}" = none ]; then
  unset VISION_LLM_PROVIDER VISION_LLM_MODEL
else
  export VISION_LLM_PROVIDER="${VISION_LLM_PROVIDER:-$LLM_PROVIDER}"
  export VISION_LLM_MODEL="${VISION_LLM_MODEL:-$LLM_MODEL}"
fi

# --- size limits from the cgroup ------------------------------------------
mem_bytes=""
if [ -r /sys/fs/cgroup/memory.max ]; then mem_bytes="$(cat /sys/fs/cgroup/memory.max)";
elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then mem_bytes="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"; fi
case "$mem_bytes" in ""|max|*[!0-9]*) mem_mb=0 ;; *) mem_mb=$((mem_bytes / 1048576)) ;; esac
[ "$mem_mb" -gt 1048576 ] && mem_mb=0   # "unlimited" as a huge number

cpus=2
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r q p < /sys/fs/cgroup/cpu.max || true
  if [ "${q:-max}" != max ] && [ "${p:-0}" -gt 0 ]; then cpus=$(( (q + p - 1) / p )); fi
fi
[ "$cpus" -lt 1 ] && cpus=1
[ "$cpus" -gt 4 ] && cpus=4
# Railway shows the host's 32+ CPUs inside a small service: cap Go's threads.
export GOMAXPROCS="${GOMAXPROCS:-$cpus}"
if [ "$mem_mb" -gt 0 ]; then
  export GOMEMLIMIT="${GOMEMLIMIT:-$((mem_mb * 60 / 100))MiB}"
fi
# Page images for vision OCR: upstream allows 600 DPI and 40 MP per page
# (about 160 MB of raw pixels). Below 1 GB use 300 DPI / 12 MP, which still
# gives an A4 page at full 300 DPI and keeps OCR inside 512 MB.
if [ "$mem_mb" -gt 0 ] && [ "$mem_mb" -lt 900 ]; then
  export IMAGE_MAX_RENDER_DPI="${IMAGE_MAX_RENDER_DPI:-300}"
  export IMAGE_MAX_TOTAL_PIXELS="${IMAGE_MAX_TOTAL_PIXELS:-12000000}"
  export IMAGE_MAX_PIXEL_DIMENSION="${IMAGE_MAX_PIXEL_DIMENSION:-6000}"
  log "memory limit ${mem_mb} MB: page rendering capped at ${IMAGE_MAX_RENDER_DPI} DPI / ${IMAGE_MAX_TOTAL_PIXELS} px"
fi
log "memory ${mem_mb:-?} MB, GOMAXPROCS=$GOMAXPROCS, GOMEMLIMIT=${GOMEMLIMIT:-unset}"

# --- state on the volume ------------------------------------------------------
# paperless-gpt keeps everything relative to its working directory:
# prompts/ (prompt templates and AI workflows), config/ (UI settings),
# db/ (undo history and OCR runs). Run it from the volume so all of it persists.
mkdir -p "$DATA_DIR/prompts" "$DATA_DIR/config" "$DATA_DIR/db" "$DATA_DIR/home" /tmp/paperless-gpt-cache
ln -sfn /app/default_prompts "$DATA_DIR/default_prompts"
chown -R "$PUID:$PGID" "$DATA_DIR" /tmp/paperless-gpt-cache 2>/dev/null || true
export PAPERLESS_GPT_CACHE_DIR="${PAPERLESS_GPT_CACHE_DIR:-/tmp/paperless-gpt-cache}"
export LISTEN_INTERFACE="127.0.0.1:$APP_PORT"
cd "$DATA_DIR"

ADMIN_PASSWORD_HASH="$(caddy hash-password --plaintext "$ADMIN_PASSWORD")"
export ADMIN_PASSWORD_HASH
unset ADMIN_PASSWORD

log "starting paperless-gpt $(cat /app/RAILWAY_TEMPLATE_VERSION 2>/dev/null) on 127.0.0.1:$APP_PORT (Paperless-ngx: $PAPERLESS_BASE_URL, LLM: $LLM_PROVIDER/$LLM_MODEL)"
su-exec "$PUID:$PGID" env HOME="$DATA_DIR/home" /app/paperless-gpt &
APP_PID=$!

# Open the public port only once the app answers, so /healthz means "ready".
# Startup waits for Paperless-ngx (up to 30 s per call when it is unreachable).
i=0
until wget -q -O /dev/null "http://127.0.0.1:$APP_PORT/api/version" 2>/dev/null; do
  kill -0 "$APP_PID" 2>/dev/null || { wait "$APP_PID" 2>/dev/null || true; die "paperless-gpt stopped during startup (see the log lines above)."; }
  i=$((i + 1)); [ "$i" -lt 560 ] || die "paperless-gpt did not answer within 280 s."
  sleep 0.5
done

log "starting Caddy on :$PORT (basic auth user: $ADMIN_USERNAME)"
su-exec "$PUID:$PGID" caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

trap 'kill -TERM "$APP_PID" "$CADDY_PID" 2>/dev/null; exit 0' TERM INT

# BusyBox "wait -n" doesn't return on the first child exit, so poll both.
while :; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    rc=0; wait "$APP_PID" 2>/dev/null || rc=$?
    kill -TERM "$CADDY_PID" 2>/dev/null || true
    die "paperless-gpt stopped unexpectedly (exit $rc); exiting so Railway restarts the service."
  fi
  if ! kill -0 "$CADDY_PID" 2>/dev/null; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    die "Caddy stopped unexpectedly; exiting so Railway restarts the service."
  fi
  sleep 2
done
