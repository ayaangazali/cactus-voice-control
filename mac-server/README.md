# Cactus Voice — Mac Gateway

Receives voice intents from the iPhone Cactus app and runs [`mobile-use`](https://github.com/minitap-ai/mobile-use) against the iOS Simulator (or any device `idb` can see).

## Install

```bash
brew install uv idb-companion
brew tap facebook/fb && brew install idb-companion   # if first time
uv sync --all-extras
cp .env.example .env
```

## Run

```bash
uv run cactus-voice-mac --pair
```

`--pair` prints a terminal QR and auto-fills `CACTUS_TOKEN` in `.env` if missing.

## Test

```bash
uv run pytest -q
```

## Endpoints

See [../docs/PROTOCOL.md](../docs/PROTOCOL.md). TL;DR: `GET /health`, `POST /command`, `GET /status/:id` (SSE), `POST /cancel/:id`. All require `Authorization: Bearer $CACTUS_TOKEN`.
