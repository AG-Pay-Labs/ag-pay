# HTTP API overview

## Contract status

This document describes the implemented `0.1.0` prototype API. The running FastAPI OpenAPI document at `/docs` is authoritative for exact validation constraints. Production hardening that is intentionally not part of the current contract is called out separately rather than presented as shipped behavior.

All application routes are JSON over HTTP(S) under `/api/v1`; health routes are at the service root. In any non-local environment, TLS is mandatory.

## Conventions

### Authentication

- Human endpoints accept `Authorization: Bearer <user-access-token>`. User access tokens are short-lived JWTs with `type=user`.
- Agent endpoints under `/api/v1/agent/*` accept an opaque `agt_...` bearer token returned once by the pairing handshake. Only its keyed hash is stored.
- `/auth/register`, `/auth/login`, and `/agent/handshake` are unauthenticated entry points.
- A human token cannot authenticate as an agent, and an agent token cannot authenticate as a human.

The Next.js web app does not place the human bearer token in browser JavaScript storage. Its same-origin auth routes establish an HttpOnly cookie, and its `/api/backend/*` BFF route adds the bearer header server-side for an explicit allowlist of human endpoints. The FastAPI paths and authentication rules in this document remain authoritative; the BFF is a browser transport/session boundary, not a second business API.

The BFF does not proxy `/api/v1/agent/*`. Agent pairing exchange, heartbeat,
cart proposal/status, legacy sandbox completion, and checkout-event reads are
calls from the agent runtime directly to FastAPI.

The BFF allowlist includes the human payment-policy list/update routes. Policy authorization and evaluation remain in FastAPI.

### Response shapes

Collection endpoints currently return plain JSON arrays. Public identifiers are UUIDs. Timestamps are RFC 3339 values. Monetary values are fixed-precision decimal amounts plus uppercase three-letter currency codes.

FastAPI validation errors use its standard `422` representation. Domain errors currently use:

```json
{
  "detail": "Payment method is not assigned to this agent"
}
```

Expected status codes include `400`/`422` for invalid input, `401` for missing or invalid authentication, `403` for an authenticated but disallowed action, `404` for absent or out-of-tenant resources, and `409` for duplicates or invalid state transitions.

Owner-scoped lookups generally return `404` for another user's resource to limit identifier probing.

### Idempotency and checkout ambiguity

The CORS configuration reserves the `Idempotency-Key` header, but `0.1.0` does
not persist or enforce general request idempotency keys. Managed checkout does
persist a unique execution per cart item, uses database row locks and a worker
lease, serializes execution per Issuing card with a PostgreSQL advisory lock,
and records an irreversible `submitted_at` boundary. A stale execution can be
claimed again only before card disclosure. Any ambiguous condition after that
boundary becomes `outcome_unknown` and is never automatically retried.

## Authentication

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/v1/auth/register` | None | Create a user from `username` and `password`; return an access token |
| `POST` | `/api/v1/auth/login` | None | Exchange username/password for an access token |
| `GET` | `/api/v1/auth/me` | User | Return the authenticated user |

Registration normalizes the username to lowercase and requires a password of at least ten characters. The prototype has no refresh token, logout/revocation endpoint, email verification, or password recovery.

Example registration:

```json
{
  "username": "alex",
  "password": "a-long-unique-passphrase"
}
```

## Human agent management

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/v1/agents` | User | Create an agent and return its initial pairing token once |
| `GET` | `/api/v1/agents` | User | List the user's agents and connection state |
| `GET` | `/api/v1/agents/{agent_id}` | User | Read one owned agent |
| `POST` | `/api/v1/agents/{agent_id}/pairing-token` | User | Rotate the one-time pairing token and invalidate an existing agent token |
| `DELETE` | `/api/v1/agents/{agent_id}` | User | Revoke the agent and its authentication material |

Creating an agent accepts `name` and optional `description`. In the same workflow, the backend creates its default `always` payment policy. The response includes `pairing_token` and `pairing_expires_at`; those fields do not appear on subsequent reads. Rotating the pairing token intentionally disconnects the current installation so it can be paired again.

An agent has a persisted enrollment status of `pending`, `active`, or `revoked`. The response also has `connection_state`: `pending`, `online`, `offline`, or `revoked`. In `0.1.0`, this display value is derived from the persisted `last_seen_at` and configured online window. Heartbeats also write a Redis presence TTL, but current response serialization does not read it.

## Agent pairing and heartbeat

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/v1/agent/handshake` | Pairing token in body | Exchange a valid one-time pairing token for an agent bearer token |
| `POST` | `/api/v1/agent/heartbeat` | Agent | Refresh online presence and `last_seen_at` |

Handshake request:

```json
{
  "pairing_token": "pair_...",
  "instance_id": "openclaw-laptop-01",
  "software_version": "0.1.0",
  "capabilities": ["cart-items.v1", "heartbeat.v1", "checkout-events.v1"]
}
```

Handshake response:

```json
{
  "agent_id": "d715517a-9c49-4a4a-9230-f7a533f14628",
  "agent_access_token": "agt_...",
  "token_type": "bearer",
  "expires_at": "2027-08-04T12:00:00Z"
}
```

The access token is returned once and must be stored by the agent runtime as a secret. See [Agent pairing and security](./agent-pairing-and-security.md) for the implemented handshake and its hardening path.

## Payment methods and billing details

The prototype embeds a personal or business billing profile in each payment method rather than exposing a separate billing-profile resource.

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/v1/payment-methods` | User | Attach provider-tokenized card metadata and billing details |
| `GET` | `/api/v1/payment-methods` | User | List owned payment methods with safe card metadata |
| `DELETE` | `/api/v1/payment-methods/{payment_method_id}` | User | Disable the method and remove current agent assignments |

Create accepts an opaque `provider_payment_method_id`, never a PAN or CVC. The
prototype fails closed to `provider=prototype-vault` with a `pm_...` reference
for legacy and development-only Stripe-hosted test flows, or
`provider=stripe_issuing` with an `ic_...` reference for configured-merchant
managed checkout. Common card fields are `display_name`,
`provider`, `card_brand`, `card_last4`, `expiry_month`, and `expiry_year`.

`billing_details` is a discriminated union.

Personal example:

```json
{
  "display_name": "Personal Visa",
  "provider": "prototype-vault",
  "provider_payment_method_id": "pm_sandbox_card123",
  "card_brand": "visa",
  "card_last4": "4242",
  "expiry_month": 12,
  "expiry_year": 2030,
  "billing_details": {
    "type": "personal",
    "full_name": "Alex Example",
    "email": "alex@example.test",
    "phone": null,
    "address": {
      "line1": "1 Example Street",
      "line2": null,
      "city": "Madrid",
      "region": "Madrid",
      "postal_code": "28001",
      "country": "ES"
    }
  }
}
```

Business details replace `full_name` with `legal_name`, `vat_number`, optional `registration_number`, and `contact_name`; contact email/phone and address remain present.

The create endpoint accepts safe display metadata without contacting a provider.
For managed Stripe Issuing checkout, the worker retrieves the virtual card and
requires its brand/last-four/expiry to match plus provider-owned
`agpay_owner_id` metadata to match the execution owner before using it. Legacy
references remain presentation/test data. Provider-hosted onboarding is still
required before production.

## Agent/payment-method assignments

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `PUT` | `/api/v1/agents/{agent_id}/payment-methods/{payment_method_id}` | User | Idempotently assign an active owned method to an owned agent |
| `GET` | `/api/v1/agents/{agent_id}/payment-methods` | User | List methods assigned to the agent |
| `DELETE` | `/api/v1/agents/{agent_id}/payment-methods/{payment_method_id}` | User | Remove the assignment |

One method may be assigned to multiple agents and one agent may have multiple methods. The backend verifies common ownership for both resources.

## Per-agent payment policies

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/api/v1/payment-policies` | User | List one owner-scoped policy per owned agent, backfilling `always` for legacy agents |
| `PATCH` | `/api/v1/agents/{agent_id}/payment-policy` | User | Replace the owned agent's review mode and optional threshold |

Creating an agent also creates an `always` policy. Modes are:

| `mode` | Requires human review when… |
| --- | --- |
| `always` | Every cart item is proposed. |
| `subscriptions_only` | `billing_period` is monthly or yearly. |
| `above_amount` | `unit_price × quantity` is strictly greater than the configured threshold. |
| `subscriptions_or_above_amount` | The item is recurring or its total is strictly greater than the threshold. |
| `never` | Never because of the policy alone. |

The table applies only to unmanaged proposals. Managed checkout always requires
the human approval endpoint regardless of policy mode.

An amount equal to the threshold is eligible for automatic approval. Both `threshold_amount` and `threshold_currency` are required for the two amount modes and prohibited for the other modes. The amount is non-negative with at most two decimal places; currency is an uppercase three-letter code. If proposal currency differs from threshold currency, evaluation fails safe and requires review rather than converting money.

Example threshold update:

```json
{
  "mode": "subscriptions_or_above_amount",
  "threshold_amount": "20.00",
  "threshold_currency": "USD"
}
```

For `always`, `subscriptions_only`, or `never`, send both threshold fields as `null` or omit them. Policy updates affect proposals created after the update; they do not reclassify existing cart items. A policy affects only the `proposed` versus `approved` control-plane transition. It does not charge a card, create a provider authorization, or give the agent raw credentials. In particular, `never` is not an unlimited real issuer permission.
Managed checkout ignores automatic-approval eligibility and always remains
`proposed` for the human approval endpoint.

## Agent cart API

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/api/v1/agent/cart-items` | Agent | Propose an item, purchase credential, and optional managed-checkout specification |
| `GET` | `/api/v1/agent/cart-items` | Agent | List the authenticated agent's own items; optional `status` query |
| `GET` | `/api/v1/agent/cart-items/{cart_item_id}` | Agent | Read one owned proposal and sanitized execution state |
| `GET` | `/api/v1/agent/checkout-events` | Agent | Read durable terminal checkout events after an integer cursor |
| `POST` | `/api/v1/agent/cart-items/{cart_item_id}/purchase` | Agent | Record a legacy external/sandbox result only when no managed execution exists |

The backend derives `agent_id` and owner from the agent token. A proposal includes the product facts, the agent's reason, recurrence, and the merchant account the human can later use:

```json
{
  "title": "Noise-cancelling headphones",
  "description": "Black, over-ear model selected from the approved shortlist.",
  "product_url": "https://merchant.example/products/headphones",
  "merchant": "Example Merchant",
  "reason": "Best match under the user's stated travel budget.",
  "quantity": 1,
  "unit_price": "199.00",
  "currency": "EUR",
  "billing_period": null,
  "account": {
    "email": "alex+merchant@example.test",
    "password": "a-unique-merchant-password",
    "login_url": "https://merchant.example/login"
  },
  "checkout": {
    "adapter": "example_merchant",
    "checkout_url": "https://merchant.example/checkout/cart-123"
  }
}
```

`billing_period` is `monthly`, `yearly`, or `null`. The merchant password is
encrypted at rest and never returned in normal cart or purchase responses.
Managed checkout currently requires `billing_period=null`; recurring proposals
remain eligible only for the legacy sandbox/external completion path until an
adapter can verify renewal amount and interval.

On creation, FastAPI evaluates the owner-configured policy against total amount,
currency, and recurrence for an unmanaged proposal. Such a proposal can return
`approved` with a server-selected active assigned method when the rule permits.
A proposal containing `checkout` always returns `proposed`, with no selected
method or execution, regardless of policy. Only the human approval route can
select a supported assigned method and queue it.

`checkout` is optional and both fields are required together. It cannot be
combined with a non-null `billing_period`. The adapter key
must exist in operator-owned platform configuration and the checkout URL origin
must be one of its exact HTTPS origins. The amount must also map exactly to the
minor-unit exponent of a currency in the worker's explicit Stripe presentment
set. The configured merchant total element must show that explicit ISO code;
bare currency symbols are not accepted. When the human approves the item,
FastAPI creates one `queued` execution in the same
transaction. The cart response includes a sanitized `execution` summary with
status, approved amount/currency, attempt count, safe error code/message, and
timestamps. Human cart responses additionally include ordered
`status_history` entries (`status`, `attempt_count`, safe error code/message,
and `occurred_at`) plus the safe merchant order reference and Browserbase
session ID needed for operator inspection. Agent cart responses omit that
history and those human-only fields. Neither response contains a provider card
reference, Browserbase connect URL, card data, or provider secret.

When the development-only built-in adapter is enabled, its key is
`stripe-hosted` and its request bootstrap URL is
`https://checkout.stripe.com/`. The API still freezes the agent-supplied product
facts and requires human approval. The worker—not the agent—then creates a new
Stripe `cs_test_...` Checkout Session containing the exact approved title,
quantity, amount, currency, and execution metadata and replaces the bootstrap
URL for that execution. The original `product_url` is retained on the proposal
but is not treated as a cart/order integration with that merchant.

Successful human purchase responses can include a sanitized
`merchant_order_reference` for reconciliation. The agent checkout-event feed
does not include it, an issuer reference, or any browser identifier.

For a managed item, only the trusted worker can create the purchase. The legacy
completion endpoint returns `409` if an execution exists. For an unmanaged
item, completion is still accepted only for the originating agent, only from
`approved`, and only when the payment method remains active and assigned. Its
submitted amount and currency must exactly match the proposal.

Completion body:

```json
{
  "amount": "199.00",
  "currency": "EUR",
  "provider_reference": "sandbox-order-123",
  "receipt_url": "https://merchant.example/orders/123",
  "next_billing_at": null
}
```

This legacy endpoint records a result; it does not charge a card. Managed
checkout instead uses the dedicated Browserbase/Stripe Issuing worker described
in [Managed checkout](./managed-checkout.md).

The checkout-event endpoint accepts `after_cursor` (default `0`) and `limit`
(`1` to `500`). It returns ordered, agent-scoped terminal events plus
`next_cursor`. Event fields are limited to an event ID, request ID, status,
optional purchase ID, amount, currency, fixed error code, and occurrence time.

## Human cart API

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/api/v1/cart-items` | User | List owned cart items; optional `status` query |
| `GET` | `/api/v1/cart-items/{cart_item_id}` | User | Inspect one owned item |
| `POST` | `/api/v1/cart-items/{cart_item_id}/approve` | User | Approve a proposed item with an assigned payment method |
| `POST` | `/api/v1/cart-items/{cart_item_id}/cancel` | User | Cancel a proposed item |
| `POST` | `/api/v1/cart-items/{cart_item_id}/credential/reveal` | User + current password | Reveal the merchant email/password and login URL |

Approve body:

```json
{
  "payment_method_id": "f233b42a-f735-4d85-9479-746f9f70571e",
  "note": "Approved for the quoted price."
}
```

Cancel accepts an optional `note`. Only `proposed` items can currently be
manually approved or cancelled. Items approved by policy are always unmanaged;
they appear in the web Approved queue but cannot be cancelled through the
current state machine. Credential reveal requires the platform user's current
password in the body and should be treated as highly sensitive; the response
must not be cached or logged.

The cart decision lifecycle remains:

```text
proposed -> approved -> purchased
    |
    +-----> cancelled

unmanaged policy + active assignment -> approved -> purchased
```

For items with `checkout`, approval additionally creates:

```text
queued -> running -> succeeded
                  -> failed
                  -> action_required
                  -> outcome_unknown
```

Only `succeeded` transitions the cart item to `purchased`. The other terminal
execution states retain the approved cart record for inspection and
reconciliation; there is no automatic retry from `outcome_unknown`.

## Purchases and subscriptions

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/api/v1/purchases` | User | List the user's successful purchase records |
| `GET` | `/api/v1/purchases/{purchase_id}` | User | Read one owned purchase and source-item snapshot |
| `GET` | `/api/v1/subscriptions` | User | List recurring commitments |
| `PATCH` | `/api/v1/subscriptions/{subscription_id}` | User | Update known status and next billing time |

Subscription status is `active`, `paused`, or `cancelled`; period is `monthly` or `yearly`. Updating this record tracks local knowledge only—it does not claim to cancel or modify a subscription at the merchant.

Purchase status values are `completed`, `failed`, and `refunded`, although both
the worker and legacy completion path currently create only verified/completed
purchase rows. Failed and ambiguous managed attempts live on the execution and
event records; refund processing is not implemented.

## Health

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/health/live` | None | Process liveness |
| `GET` | `/health/ready` | None | PostgreSQL and Redis readiness |

Health responses contain only a simple message.

## Known contract gaps before production payments

- Persistent request-wide idempotency keys and request fingerprinting.
- Explicit approval expiry and an all-in ceiling/quote for tax and shipping,
  rather than the current exact proposal-only approval.
- One-execution virtual cards or issuer-enforced authorization bounds; a review
  threshold is not a real spend limit.
- Signed/proof-of-possession pairing and agent credential rotation.
- Provider-hosted card onboarding/metadata verification, signed webhooks, and
  operator reconciliation actions. The current UI accepts opaque references.
- A general durable outbox and audit log. Checkout terminal events are durable,
  while Redis publication and other business events remain best effort.
- More reviewed merchant adapters; the implemented executor rejects arbitrary
  merchants and interactive challenges.
- Cursor pagination and bounded page sizes.
- Refresh-session management, logout, recovery, and step-up token semantics.
- Request-wide safe error envelope and correlation ID.

These are architecture roadmap items, not optional polish for production financial activity.
