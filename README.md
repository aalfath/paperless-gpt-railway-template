[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/paperless-gpt-1?utm_medium=integration&utm_source=button&utm_campaign=paperless-gpt)

# paperless-gpt on Railway

One-click Railway template for [paperless-gpt](https://github.com/icereed/paperless-gpt) (MIT): an LLM and vision-OCR helper for a [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) archive you already run. It suggests titles, tags, correspondents, document types and dates, and re-reads poor scans with a vision model.

- **App:** paperless-gpt **v0.31.0**, official image `icereed/paperless-gpt:v0.31.0@sha256:d668941a829552cc0eddbc7c22506b3480dfbf61bd0d6eae881ad9fcfe2de70c`
- **Front door:** Caddy 2.11.9 (`caddy:2.11.9-alpine@sha256:003a9780…`) with HTTP basic auth, because paperless-gpt has no login of its own and its API can read and rewrite your documents and spend your LLM key.

## What gets deployed

One service, `paperless-gpt`, built from this repo's `Dockerfile`:

| Part | What it does |
|---|---|
| Caddy on `$PORT` (8080) | Public URL. Every path needs the generated password, except `/healthz`, which Railway uses as its health check (it answers only when paperless-gpt is up). |
| paperless-gpt on `127.0.0.1:8081` | Web UI and API, reachable only through Caddy. Talks to your Paperless-ngx and your LLM provider. |
| Volume at `/data` | `prompts/` (prompt templates and AI workflows), `config/` (settings made in the UI), `db/` (undo history and OCR run log). |

No database or other service is needed. Your documents stay in Paperless-ngx.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `PAPERLESS_BASE_URL` | (you enter it) | Address of your Paperless-ngx, e.g. `https://paperless.YOUR-DOMAIN`. If Paperless-ngx runs in the same Railway project, use its private address, e.g. `http://${{Paperless-ngx.RAILWAY_PRIVATE_DOMAIN}}:8000`. |
| `PAPERLESS_API_TOKEN` | (you enter it) | In Paperless-ngx: My Profile, API Auth Token. |
| `OPENAI_API_KEY` | (you enter it) | Key for OpenAI or any OpenAI-compatible API (OpenRouter, Groq, DeepSeek, a LiteLLM gateway). |
| `OPENAI_BASE_URL` | `https://api.openai.com/v1` | Change it for another OpenAI-compatible API, e.g. `https://openrouter.ai/api/v1`. |
| `LLM_MODEL` | `gpt-5-mini` | Model used for suggestions and, unless you set `VISION_LLM_MODEL`, for vision OCR. It must accept images for OCR. |
| `ADMIN_USERNAME` | `admin` | Login for the password prompt. |
| `ADMIN_PASSWORD` | generated | 24 random characters. Find it in the service's Variables tab. |
| `PORT` | `8080` | Port Caddy listens on; the public domain points to it. |

Optional, add them yourself when you need them (all upstream variables work, see [upstream's list](https://github.com/icereed/paperless-gpt#environment-variables)):

- `LLM_PROVIDER` = `anthropic`, `googleai`, `mistral` or `ollama`, with that provider's key (`ANTHROPIC_API_KEY`, `GOOGLEAI_API_KEY`, `MISTRAL_API_KEY`) or `OLLAMA_HOST`. The start script only requires `OPENAI_API_KEY` when the provider is `openai`.
- `VISION_LLM_PROVIDER` / `VISION_LLM_MODEL` for a different OCR model, or `VISION_LLM_PROVIDER=none` to turn LLM OCR off.
- `AUTO_TAG`, `AUTO_OCR_TAG`, `CREATE_NEW_TAGS`, `PDF_UPLOAD`, `OCR_PROVIDER` (`azure`, `google_docai`, `mistral_ocr`, `docling`) and the rest of upstream's settings.
- `PAPERLESS_PUBLIC_URL` if `PAPERLESS_BASE_URL` is a private address, so the UI's links to documents open in your browser.

## After deploying

1. Open the public URL and log in as `admin` with `ADMIN_PASSWORD` from the Variables tab.
2. In Paperless-ngx, tag a document `paperless-gpt` (manual review in the paperless-gpt UI) or `paperless-gpt-auto` (processed in the background). For OCR, use `paperless-gpt-ocr-auto`, or the OCR page in the UI.
3. Review the suggestions and apply them. They're written back to Paperless-ngx, and the History page can undo them.

If the URL or token is wrong, paperless-gpt still starts and shows the Paperless-ngx error in the UI and the logs. Fix the variable and Railway redeploys.

## Resources

paperless-gpt runs in **0.5 GB RAM** (Railway's Free plan limit per service). Tested on Railway at 0.5 GB / 1 vCPU: about 110 MB idle, about 310 MB for a few seconds at boot while the PDF renderer compiles, and a peak of about 390 MB during vision OCR of a 5-page A4 scan. Below 900 MB the start script renders pages at 300 DPI / 12 megapixels at most (upstream allows 600 DPI / 40 MP), which is still full resolution for an A4 page at 300 DPI. Give the service 1 GB if you raise those limits or OCR very large pages. `GOMAXPROCS` and `GOMEMLIMIT` are set from the service's CPU and memory limit.

If paperless-gpt or Caddy stops unexpectedly, the container exits non-zero so Railway's `ON_FAILURE` restart policy brings it back.

## Updates

This template builds from this repository, so Railway shows an "update available" notice in your project when `main` changes. Check [CHANGELOG.md](CHANGELOG.md) first (breaking changes are listed first), then apply it from the Railway dashboard. Your volume (prompts, settings, history) is kept.

## Local test

```sh
docker build -t paperless-gpt-railway .
docker run --rm -p 8080:8080 -v pgpt:/data \
  -e ADMIN_PASSWORD=change-me-now-please \
  -e PAPERLESS_BASE_URL=https://paperless.YOUR-DOMAIN -e PAPERLESS_API_TOKEN=... \
  -e OPENAI_API_KEY=sk-... paperless-gpt-railway
```

paperless-gpt is © Icereed and contributors, MIT licence. This wrapper is not affiliated with the paperless-gpt or Paperless-ngx projects.
