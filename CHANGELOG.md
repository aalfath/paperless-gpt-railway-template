# Changelog

## v0.31.0 (2026-11-23)

First release of this template.

- paperless-gpt v0.31.0 (official image, pinned by digest).
- Caddy 2.11.9 basic auth in front, with a generated password; paperless-gpt listens on loopback only.
- All state (prompts, AI workflows, UI settings, undo history, OCR run log) on the `/data` volume.
- Defaults for an OpenAI-compatible API (`OPENAI_BASE_URL`, `LLM_MODEL=gpt-5-mini`); vision OCR uses the same model unless set otherwise.
- Memory-aware limits for Railway's 0.5 GB plan: `GOMAXPROCS`, `GOMEMLIMIT` and page-render size are set from the cgroup.
