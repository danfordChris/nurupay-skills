---
name: nurupay
description: Integrate NuruPay, the Tanzanian mobile-money payment API (M-Pesa, Airtel Money, Mixx by Yas, HaloPesa, T-Pesa). Use when writing, reviewing, or debugging code that charges a customer's phone through NuruPay, handles NuruPay webhooks, or uses np_test_sk_/np_live_sk_ keys.
---

# NuruPay integration

NuruPay charges a customer's mobile-money wallet with a USSD push: you send a phone number and an amount, the customer approves a PIN prompt, and NuruPay tells you the result by webhook.

Docs: https://docs.nurupay.io · Full docs as Markdown: https://docs.nurupay.io/llms-full.txt · OpenAPI: https://docs.nurupay.io/openapi.yaml

If the NuruPay MCP server is connected (`https://docs.nurupay.io/mcp`), call `search_docs`, `read_doc`, or `get_openapi_spec` for anything not covered here instead of guessing.

## Rules that must hold in every integration

1. **Secret keys stay on the server.** Never put `np_test_sk_…` or `np_live_sk_…` in browser JavaScript, a mobile app, or a repository. Read them from an environment variable such as `NURUPAY_KEY`.
2. **Send `Idempotency-Key` on every `POST`** (a fresh UUID per logical payment). On a timeout, `5xx`, or `429`, retry with the **same** key and body.
3. **Use your order ID as `reference`.** It must be unique per mode; reusing it returns `409 duplicate_reference`, which prevents charging an order twice.
4. **Only `status: "succeeded"` means paid.** `failed` and `expired` are also final. Never mark an order paid from a browser redirect, a `202` response, or elapsed time.
5. **Verify every webhook signature** on the raw request bytes, reject timestamps older than 5 minutes, and deduplicate on the event `id`.
6. **Answer webhooks with `2xx` within 10 seconds**, then do slow work in the background.
7. **Amounts are whole Tanzanian shillings** (`15000` = TZS 15,000), from 100 to 5,000,000. No decimals, no cents.

## API basics

- Base URL: `https://api.nurupay.io`
- Auth header: `Authorization: Bearer <secret key>`
- The key decides the mode: `np_test_sk_` simulates payments, `np_live_sk_` moves real money. Test and live data never mix.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/v1/whoami` | Check which account and mode a key belongs to |
| `POST` | `/v1/collections` | Charge a phone (returns `202`, `status: "created"`) |
| `GET` | `/v1/collections/{id}` | Current state of one collection |
| `GET` | `/v1/collections?limit=&starting_after=` | Newest first; page while `has_more` is true |
| `GET` | `/v1/balance` | `pending`, `available`, `reserved` for the key's mode |
| `GET` | `/v1/events/{id}` | Re-fetch a webhook event |

### Create a collection

```http
POST /v1/collections
Authorization: Bearer $NURUPAY_KEY
Content-Type: application/json
Idempotency-Key: 4f6c2b1e-8d0a-4c55-9e7b-3a2f1c0d9e8b

{"amount": 15000, "phone": "0754123456", "reference": "ORDER-1029", "description": "Order 1029", "metadata": {"cart_id": "abc"}}
```

- `phone` accepts `07XXXXXXXX`, `06XXXXXXXX`, `2557…`, or `+2557…`. The network is detected from the prefix; pass `channel` only if the customer moved their number to another network.
- `channel`: `MPESA_TZ` (074, 075, 076), `AIRTEL_MONEY_TZ` (068, 069, 078), `MIXX_BY_YAS` (065, 067, 071, 077), `HALOPESA` (061, 062), `TPESA` (073).
- `description` is up to 255 characters; `metadata` holds up to 20 keys (4 KB), returned unchanged.
- The `fee` is fixed at creation and deducted from what you receive.

Lifecycle: `created → pending → succeeded | failed | expired`. A collection expires after 30 minutes without approval.

### Minimal server example (Node.js 18+)

```js
import crypto from 'node:crypto';

export async function chargePhone({ orderId, amount, phone }) {
  const res = await fetch('https://api.nurupay.io/v1/collections', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.NURUPAY_KEY}`,
      'Content-Type': 'application/json',
      // Persist this with the order so a retry reuses it.
      'Idempotency-Key': crypto.randomUUID(),
    },
    body: JSON.stringify({ amount, phone, reference: orderId }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`${body.error.code}: ${body.error.message} (${body.error.request_id})`);
  return body; // body.id = "col_…"; wait for the webhook before fulfilling the order
}
```

## Webhooks

Events: `collection.succeeded`, `collection.failed` (see `data.failure_code`), `collection.expired`. `data` is the full collection.

Header: `NuruPay-Signature: t=<unix seconds>,v1=<hex HMAC-SHA256 of "<t>.<raw body>" with the endpoint's whsec_ secret>`

```js
import crypto from 'node:crypto';

// rawBody must be the exact bytes received; parsing and re-serialising JSON breaks the signature.
export function verifyNuruPaySignature(rawBody, header, secret, toleranceSeconds = 300, now = Date.now()) {
  const parts = Object.fromEntries(header.split(',').map((p) => p.trim().split('=', 2)));
  const t = Number(parts.t);
  if (!Number.isInteger(t) || !parts.v1) return false;
  if (Math.abs(now / 1000 - t) > toleranceSeconds) return false;
  const expected = crypto.createHmac('sha256', secret).update(`${t}.${rawBody}`).digest('hex');
  const a = Buffer.from(expected, 'hex');
  const b = Buffer.from(parts.v1, 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
```

```python
import hashlib, hmac, time

def verify_nurupay_signature(raw_body: bytes, header: str, secret: str, tolerance_seconds: int = 300) -> bool:
    parts = dict(p.strip().split("=", 1) for p in header.split(",") if "=" in p)
    try:
        t, sig = int(parts["t"]), parts["v1"]
    except (KeyError, ValueError):
        return False
    if abs(time.time() - t) > tolerance_seconds:
        return False
    expected = hmac.new(secret.encode(), f"{t}.".encode() + raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, sig)
```

Framework notes: in Express use `express.raw({ type: 'application/json' })` on the webhook route; in Next.js route handlers use `await request.text()`; in Django use `request.body`; in Laravel/PHP use `file_get_contents('php://input')`.

Delivery is at least once and may be out of order: store processed event IDs, and if order matters fetch `GET /v1/collections/{id}` for the current state. Failed deliveries are retried after 1m, 5m, 30m, 2h, 6h, and 12h.

## Errors

Shape: `{"error": {"type", "code", "message", "param", "request_id"}}`. Branch on `code`; log `request_id`.

| Status | Codes | What to do |
|---|---|---|
| 400 | `invalid_phone`, `invalid_reference`, `invalid_metadata`, `idempotency_key_required`, … | Fix the request |
| 401 | `invalid_api_key`, `api_key_expired` | Check the key |
| 403 | `live_mode_not_enabled`, `merchant_suspended`, `ip_not_allowed` | Account or key setup |
| 409 | `duplicate_reference` | This order was already charged; look it up instead |
| 409 | `idempotency_key_reused`, `idempotency_request_in_progress` | Same key with a different body / still running |
| 422 | `amount_too_small`, `amount_too_large`, `unsupported_channel` | Fix amount or pass `channel` |
| 429 | `rate_limited` | Wait `Retry-After` seconds, retry with the same key (limit 50/s, burst 100 per key) |
| 500 | `internal_error` | Retry with the same idempotency key |

A declined payment is **not** an HTTP error: the collection ends `failed` with a `failure_code`: `insufficient_funds`, `customer_cancelled`, `customer_timeout`, `invalid_account`, `account_not_registered`, `limit_exceeded`, `provider_rejected`, `provider_unavailable`. Show the customer a clear message and let them retry with a new `reference`.

## Testing

With a test key, the **last three digits** of the phone number pick the outcome:

| Ends in | Result |
|---|---|
| anything else (e.g. `0754123789`) | `succeeded` |
| `001` | `failed`, `insufficient_funds` |
| `002` | `failed`, `customer_cancelled` |
| `003` | `failed`, `customer_timeout` |
| `004` | `succeeded` after an ambiguous network response |
| `005` | stays `created`, then `expired` after 30 minutes |
| `006` | `failed` immediately, `invalid_account` |

Write tests for every row before going live.

## Going live checklist

1. Every outcome above is handled and tested.
2. Webhook signatures verified; event IDs deduplicated.
3. `Idempotency-Key` on every `POST`; timeouts retried with the same key.
4. Live key only on the server, ideally restricted to the server's IPs.
5. The business is verified in the NuruPay dashboard; live webhook endpoint uses `https://`.
6. One small real payment confirmed end to end.
