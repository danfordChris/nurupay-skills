## NuruPay payments

This project uses NuruPay (https://docs.nurupay.io), a Tanzanian mobile-money payment API (M-Pesa, Airtel Money, Mixx by Yas, HaloPesa, T-Pesa). Follow these rules in any code that charges customers or handles NuruPay webhooks:

- Base URL `https://api.nurupay.io`; send `Authorization: Bearer <secret key>`. `np_test_sk_` keys simulate payments; `np_live_sk_` keys move real money. Keys live on the server only (environment variables), never in browser/mobile code or the repository.
- Send an `Idempotency-Key` header (a UUID stored with the order) on every `POST`; on a timeout, `5xx`, or `429`, retry with the same key and body.
- Use the order ID as `reference`; it is unique per mode (`409 duplicate_reference` means this order was already charged).
- Amounts are whole TZS (`15000` = TZS 15,000), 100 to 5,000,000.
- A collection is paid only when `status` is `succeeded`; `failed` and `expired` are also final. Never mark an order paid from a redirect, a `202` response, or elapsed time.
- Webhooks: verify `NuruPay-Signature` (`t=…,v1=…`, hex HMAC-SHA256 of `"<t>.<raw body>"` with the endpoint's `whsec_` secret) on the raw bytes, reject timestamps older than 5 minutes, deduplicate on the event `id`, and answer `2xx` within 10 seconds.
- Errors are `{"error": {"type", "code", "message", "param", "request_id"}}`: branch on `code`, log `request_id`. A declined payment is not an HTTP error; it ends `failed` with a `failure_code`.
- Test numbers (test keys only): a phone ending `001` fails `insufficient_funds`, `002` `customer_cancelled`, `003` `customer_timeout`, `004` succeeds after an ambiguous response, `005` expires after 30 minutes, `006` fails `invalid_account`; anything else succeeds.

Before writing NuruPay code, read the relevant page: full docs at https://docs.nurupay.io/llms-full.txt, the OpenAPI spec at https://docs.nurupay.io/openapi.yaml, or the MCP server `https://docs.nurupay.io/mcp` if it is connected.
