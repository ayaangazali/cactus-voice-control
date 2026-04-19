# Wire Protocol

All requests flow over **HTTP/1.1** on the local Wi-Fi. All routes require `Authorization: Bearer <CACTUS_TOKEN>`.

## Pairing

The Mac CLI prints a QR encoding:

```
cactus://pair?ip=<lan-ip>&port=<port>&token=<bearer-token>
```

The iOS app's Settings → Pair flow either:
1. Scans the QR (`PairingStore.parse(qrPayload:)` validates scheme, host, query items).
2. Or accepts manual entry of host + port + token.

Stored in iOS Keychain under service `com.ayaangazali.cactusvoice.pairing`.

The Mac also advertises Bonjour `_cactus._tcp.local.` for autodiscovery (future iOS browser).

## `GET /health`

```http
GET /health
Authorization: Bearer <token>
```

```json
{ "ok": true, "version": "0.1.0", "jobs": 0 }
```

## `POST /command`

Body matches `CommandIntent` (Codable on iOS, Pydantic on Mac):

```json
{
  "id": "8C0F6E3E-7A4D-4A30-9E5F-5A1F2E6E98A3",
  "instruction": "Open Gmail and list unread emails",
  "output_description": "JSON list of {sender, subject}",
  "urgency": "normal",
  "raw_transcript": "open gmail and tell me my unread emails",
  "model_id": "qwen3-1.7b-int4",
  "created_at": "2026-04-19T08:45:21Z"
}
```

Response: immediate `CommandStatus` snapshot.

```json
{ "id": "8C0F6E3E-...", "phase": "running", "message": null, "result": null }
```

Phases: `received` → `running` → (`succeeded` | `failed` | `cancelled`).

## `GET /status/{id}` — Server-Sent Events

```http
GET /status/8C0F6E3E-... HTTP/1.1
Accept: text/event-stream
Authorization: Bearer <token>
```

Each event:

```
data: {"id":"8C0F6E3E-...","phase":"running","message":null,"result":null}

data: {"id":"8C0F6E3E-...","phase":"succeeded","message":null,"result":"... last 50 stdout lines ..."}
```

The stream closes after a terminal phase.

## `POST /cancel/{id}`

```json
{ "cancelled": true }
```

Sends SIGTERM to the spawned `mobile-use` process, escalates to SIGKILL after 5 s.

## Intent JSON contract (LLM output)

The on-device LLM is constrained by a few-shot system prompt to emit:

```json
{
  "instruction": "<imperative sentence>",
  "output_description": "<shape description, or null>",
  "urgency": "normal" | "urgent"
}
```

The iOS `IntentService.extractJSON` strips any prose by slicing between the first `{` and last `}`. Validation lives in `decodeIntent`.

## Auth model

- Single shared bearer token, persisted on first run via `secrets.token_urlsafe(32)`.
- Comparison via `_safe_compare` (constant-time).
- No PKI. The threat model assumes both devices live on the user's home Wi-Fi; do **not** expose the Mac port to WAN.
