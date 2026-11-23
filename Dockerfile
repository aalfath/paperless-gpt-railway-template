# paperless-gpt for Railway
# Upstream: https://github.com/icereed/paperless-gpt (MIT), release v0.31.0.
# The official image is pinned by tag and digest; this wrapper only adds Caddy
# (HTTP basic auth in front, because paperless-gpt has no login of its own)
# and a start script that keeps all state on the Railway volume at /data.

FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy

FROM icereed/paperless-gpt:v0.31.0@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY rootfs/ /

RUN chmod 0755 /usr/local/bin/start.sh \
 && /usr/local/bin/caddy version \
 && test -x /app/paperless-gpt && test -d /app/default_prompts \
 && echo "v0.31.0" > /app/RAILWAY_TEMPLATE_VERSION

ENV PORT=8080 \
    DATA_DIR=/data \
    GIN_MODE=release

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/start.sh"]
