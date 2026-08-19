# Domain model

## Implementation status

The `0.1.0` prototype persists `User`, `Agent`, `AgentPaymentPolicy`,
`PaymentMethod`, `StoredCardCredential`, `AgentPaymentMethod`,
`PurchaseCredential`, `CartItem`,
`CheckoutExecution`, `CheckoutStatusTransition`, `CheckoutEvent`, `Purchase`,
and `Subscription`.
Personal/business billing information is embedded as a validated value object
on `PaymentMethod`.

`AgentChallenge`, reusable `MerchantAccount`, durable `AuditEvent`,
`IdempotencyRecord`, detailed `CheckoutAttempt`, and general `OutboxEvent` are
target hardening entities, not current tables. Terminal managed-checkout events
are durable in PostgreSQL; Redis Stream events remain best effort and are not a
durable audit log.

## Current relationship model

```mermaid
erDiagram
    USER ||--o{ AGENT : owns
    USER ||--o{ PAYMENT_METHOD : owns
    USER ||--o{ AGENT_PAYMENT_POLICY : owns
    AGENT ||--o| AGENT_PAYMENT_POLICY : controls_review_with
    AGENT ||--o{ AGENT_PAYMENT_METHOD : receives
    PAYMENT_METHOD ||--o{ AGENT_PAYMENT_METHOD : assigned_through
    USER ||--o{ STORED_CARD_CREDENTIAL : owns
    PAYMENT_METHOD ||--o| STORED_CARD_CREDENTIAL : may_back
    AGENT ||--o{ PURCHASE_CREDENTIAL : creates
    AGENT ||--o{ CART_ITEM : proposes
    PURCHASE_CREDENTIAL ||--|| CART_ITEM : belongs_to
    PAYMENT_METHOD o|--o{ CART_ITEM : selected_for
    CART_ITEM ||--o| CHECKOUT_EXECUTION : may_queue
    CHECKOUT_EXECUTION ||--|{ CHECKOUT_STATUS_TRANSITION : records
    CHECKOUT_EXECUTION ||--o| CHECKOUT_EVENT : terminates_with
    CART_ITEM ||--o| PURCHASE : becomes
    CHECKOUT_EVENT o|--o| PURCHASE : may_reference
    PURCHASE ||--o| SUBSCRIPTION : may_create
```

## Current entities

### User

The human tenant and authentication principal.

| Field | Meaning |
| --- | --- |
| `id` | UUID primary key |
| `username` | Unique normalized username, maximum 64 characters |
| `password_hash` | Memory-hard password hash; never plaintext |
| `is_active` | Authentication/authorization gate |
| `created_at`, `updated_at` | UTC timestamps |

Platform identity is intentionally distinct from purchase credentials used at merchants. The prototype does not require a platform email.

### Agent

One OpenClaw-like installation owned by a user.

| Field group | Representative fields |
| --- | --- |
| Ownership/display | `id`, `owner_id`, `name`, `description` |
| Enrollment | `status`, pairing-token hash/expiry, agent-token hash/expiry |
| Installation | `instance_id`, `software_version`, `capabilities` |
| Presence | `connected_at`, `last_seen_at` |
| Revocation | `revoked_at` |

Stored status is `pending`, `active`, or `revoked`. Human responses add a connection state of `pending`, `online`, `offline`, or `revoked`, derived from `last_seen_at` and the configured online window. Redis presence is written but not consulted by the current serializer.

Pairing-token and agent-token plaintext is never persisted. A token is disclosed once at creation/exchange.

### AgentPaymentPolicy

The owner-controlled, one-per-agent rule for deciding whether a new cart item waits for human review.

| Field | Meaning |
| --- | --- |
| `id`, `owner_id`, `agent_id` | UUID identity plus tenant/agent attribution |
| `mode` | `always`, `subscriptions_only`, `above_amount`, `subscriptions_or_above_amount`, or `never` |
| `threshold_amount` | Optional non-negative `NUMERIC(18,2)` used only by amount modes |
| `threshold_currency` | Optional uppercase three-letter currency used only by amount modes |
| `created_at`, `updated_at` | UTC timestamps |

New agents receive `always`. The list endpoint creates the same default for a legacy agent without a record, while the evaluator also treats a missing policy as `always`. The unique `agent_id` enforces at most one record per agent. Database and request constraints require both threshold fields for the two amount modes and prohibit them for the other modes.

The evaluator compares the cart total `unit_price × quantity`, not unit price. “Above” is strict: a total equal to the threshold does not require review. A threshold-currency mismatch or unusable threshold fails safe to review. `never` means the control plane does not request human review; it is not an issuer authorization or an unbounded real-money permission.

### PaymentMethod

A provider-tokenized or local opaque card reference plus safe display metadata
and billing details.

| Field group | Representative fields |
| --- | --- |
| Ownership/display | `id`, `owner_id`, `display_name`, `status` |
| Provider | `provider`, `provider_payment_method_id` |
| Safe card metadata | `card_brand`, `card_last4`, `expiry_month`, `expiry_year` |
| Billing | `billing_profile_type`, `billing_details` JSON |

Status is `active` or `disabled`. The unique `(owner_id, provider,
provider_payment_method_id)` constraint prevents duplicate attachment for one
user. `PaymentMethod` itself has no PAN or CVC column. For the disabled-by-
default local research rail it stores `provider=local_direct_card` and an
opaque `ldc_...` value; list/read responses remain identical safe metadata.
Disabling a local method also deletes its encrypted credential row.

`billing_profile_type` is `personal` or `business`. The validated details contain:

- personal: full name, email, optional phone, and address;
- business: legal name, VAT number, optional registration number, contact name/email/phone, and address.

Country is an ISO alpha-2 code. VAT normalization and external verification are not implemented yet. Storing billing details as JSON accelerates the prototype but separate profile/address tables may be preferable when profiles become reusable or country validation expands.

### StoredCardCredential

The one-to-one local direct-card credential behind a `PaymentMethod`.

| Field | Meaning |
| --- | --- |
| `payment_method_id`, `owner_id` | Payment-method identity plus explicit tenant scope |
| `encrypted_pan` | Fernet ciphertext produced with the dedicated direct-card key |
| `created_at`, `updated_at` | UTC timestamps |

Only the development/test direct-card enrollment route creates this row. The
worker retrieves it by both owner and payment-method ID and decrypts PAN just in
time. No CVC field exists here or in any other durable model. Approval-time CVC
is a TTL-bound, one-shot worker-memory value and is deliberately absent from
PostgreSQL and Redis.

### AgentPaymentMethod

The many-to-many authorization between an agent and a card.

The composite primary key `(agent_id, payment_method_id)` makes assignment idempotent. Creation verifies both resources share the current user. Removing an assignment blocks new approval/completion but preserves attribution through direct purchase references.

One card can serve many agents and one agent can have many cards.

### PurchaseCredential

The external merchant login created or used for one cart item, allowing the human to access the merchant after purchase.

| Field | Meaning |
| --- | --- |
| `id`, `owner_id`, `agent_id` | Identity and attribution |
| `email` | Merchant account email |
| `encrypted_password` | Fernet-encrypted password; not serialized normally |
| `login_url` | Optional merchant sign-in URL |

Each `CartItem` has exactly one credential and each credential belongs to one item. This implements the per-purchase account requirement without assuming merchant identities are safely reusable. A future reusable `MerchantAccount` may normalize credentials by canonical merchant origin.

### CartItem

The atomic cart, rationale, and human-decision unit.

| Field group | Representative fields |
| --- | --- |
| Attribution | `id`, `owner_id`, `agent_id`, `credential_id` |
| Product | `title`, `description`, `product_url`, optional `merchant`, `quantity` |
| Managed checkout | optional `checkout_adapter` and `checkout_url` |
| Rationale | `reason` |
| Proposal | `unit_price`, `currency`, optional `billing_period` |
| Decision | `status`, `selected_payment_method_id`, `decision_note`, `approved_at`, `cancelled_at` |
| Timestamps | `created_at`, `updated_at` |

The total is derived as `unit_price × quantity`. `billing_period` is `monthly`,
`yearly`, or absent. A human can select only an active payment method currently
assigned to the originating agent. An unmanaged, policy-eligible item can start
as `approved` only when the backend finds an active assigned method; otherwise
it starts as `proposed`. A managed item always starts as `proposed`. OpenClaw
creates a managed item only when the purchase tool call explicitly supplies
both `checkout_adapter` and `checkout_url`; neither the plugin nor playground
adds those fields from configuration.

Current state machine:

```mermaid
stateDiagram-v2
    [*] --> proposed: review required or no eligible card
    [*] --> approved: unmanaged policy permits + active assigned card
    [*] --> proposed: managed checkout always requires human approval
    proposed --> approved: human approves and selects card; managed item also queues job
    proposed --> cancelled: human cancels
    approved --> purchased: worker verifies managed checkout or agent records legacy success
```

Rule-approved legacy items and manually approved items share the same persisted
cart state. If both managed-checkout fields are present, only human approval
transactionally creates one execution; otherwise the item retains the legacy
external-completion path and approval queues no payment. Checkout fields are
part of the immutable proposal contract: there is no transition or update that
converts an existing legacy proposal or approval into a managed item. The agent
must create a new proposal with the complete checkout specification.
`cancelled` and `purchased` are terminal cart states.

### CheckoutExecution

The durable, one-per-cart-item managed checkout job and authorization snapshot.

| Field group | Representative fields |
| --- | --- |
| Attribution | `id`, `owner_id`, `agent_id`, `cart_item_id`, `payment_method_id` |
| Frozen grant | `adapter_key`, `adapter_config`, `approved_amount`, `currency`, `checkout_origin` |
| Resolved form | optional `resolved_form_config` JSON containing validated selectors only |
| Worker state | `status`, `attempt_count`, `lease_expires_at`, `submitted_at` |
| Safe result | `completed_at`, `error_code`, fixed `error_message`, optional `merchant_order_reference` |
| Human operations | optional `browserbase_session_id` (human API only) |

`cart_item_id` is unique. Status is `queued`, `running`, `succeeded`, `failed`,
`action_required`, or `outcome_unknown`. Approval snapshots operator-owned
adapter selectors and origins so later configuration edits cannot silently
broaden an already approved grant.

For a local direct execution, the frozen adapter must use `checkout_mode=direct`
and `payment_form_strategy=browserbase_ai`. Stagehand observes the empty form
before secrets are loaded and returns candidate payment/billing/submit controls;
the worker validates exact visible matches and allowed frame origins, then
stores only that safe map in `resolved_form_config`. The effective strategy is
frozen as resolved. PAN, CVC, merchant HTML, and model output beyond validated
selectors are not stored there. Fixed JavaScript/Playwright performs every
field mutation and click; the model cannot act or submit.

For the development-only `stripe-hosted` adapter, the frozen configuration also
records `checkout_mode=stripe_hosted_test`. The approved
URL is the complete offer-specific
`https://checkout.stripe.com/c/pay/cs_test_...#...` target, including its
fragment; a generic Stripe origin is not sufficient. The worker extracts and
freezes the `cs_test_...` session ID, opens that existing session, and requires
the allowlisted landing verification contract to report the same session/order
reference. The landing server renders that contract only after verifying the
offer, amount, currency, complete state, and paid state. The worker neither
creates the session nor holds a Stripe credential. The safe session ID can
become the human-only merchant order reference; the landing server's Stripe
verification remains external provider evidence.

The current execution model supports one-time purchases only. A cart item with
a billing period cannot create a managed execution; recurring records remain a
legacy sandbox/external flow until the merchant interval and renewal amount can
be verified.

The lease lets another worker recover a stale pre-submit execution. Once
`submitted_at` exists, stale recovery terminates as `outcome_unknown`; it never
replays the merchant submission. `browserbase_session_id` exists only for
trusted operational correlation; it is exposed only in the tenant-scoped human
execution summary and is absent from agent responses and checkout events.
Executions using the same provider/local card reference are additionally
serialized by a PostgreSQL advisory lock through result processing and the
terminal database commit.
An `action_required` or `outcome_unknown` sibling quarantines that payment
method from later managed execution. The hosted sandbox's owner-only
reconciliation can convert a proven paid `outcome_unknown` execution to
`succeeded`, create its purchase, and release the method without any payment
resubmission. Other unknown or interactive outcomes remain quarantined until a
separate operator/provider resolution.

### CheckoutStatusTransition

The append-only, human-visible lifecycle history for one checkout execution.
The approval transaction appends `queued`; every worker claim appends `running`;
a safe pre-submit retry appends another `queued`; and the outcome transaction
appends `succeeded`, `failed`, `action_required`, or `outcome_unknown`.
Verified hosted-sandbox reconciliation may append one later `succeeded`
transition after `outcome_unknown`; it records evidence resolution rather than
a second checkout attempt.

Each row stores a monotonic sequence, its execution ID, status, attempt count,
optional sanitized error code, and UTC occurrence time. Tenant ownership is
derived from the foreign-keyed execution rather than duplicated on the row.
Tenant-scoped human cart reads return the ordered history with fixed safe error
text. Agent cart responses do not expose this operational history; the separate
`CheckoutEvent` remains the agent's one-terminal-event feed.

### CheckoutEvent

The append-only terminal managed-checkout outcome consumed by the originating
agent integration.

| Field group | Representative fields |
| --- | --- |
| Cursor/identity | monotonic `cursor`, unique `event_id`, indexed `execution_id` |
| Scope | `owner_id`, `agent_id`, `cart_item_id`, optional `purchase_id` |
| Safe result | terminal `status`, `amount`, `currency`, optional `error_code`, `created_at` |

An execution normally emits one terminal event. A hosted-sandbox execution that
first emitted `outcome_unknown` emits one later `succeeded` event after verified
owner reconciliation, so an agent that already consumed the ambiguity learns
the final result. Purchase uniqueness and the reconciliation transaction make
that resolution idempotent. The agent endpoint scopes by authenticated
`agent_id` and orders by cursor. No merchant-controlled error string,
Browserbase identifier, provider card reference, or payment credential is
present.

### Purchase

The record created when either the trusted worker verifies managed checkout or
the originating agent reports a legacy sandbox/external completion.

| Field group | Representative fields |
| --- | --- |
| Attribution | `id`, `owner_id`, `agent_id`, `cart_item_id`, `payment_method_id` |
| Result | `status`, `amount`, `currency`, `provider_reference`, optional `merchant_order_reference`, optional `receipt_url` |
| Time | `purchased_at`, `created_at`, `updated_at` |

`cart_item_id` is unique, preventing more than one purchase row per item. `(payment_method_id, provider_reference)` is also unique. Current statuses are `completed`, `failed`, and `refunded`, although the implemented completion route creates only `completed`.

The human purchase response is assembled with the source cart item's product
and account-email snapshot. A sanitized merchant order reference supports
manual reconciliation; it is intentionally absent from the OpenClaw event.
Deleting an agent/card referenced by purchases is restricted or converted to a
soft state change.

### Subscription

A recurring commitment created automatically when a purchased cart item has a billing period.

| Field | Meaning |
| --- | --- |
| `id`, `owner_id`, `agent_id`, `purchase_id` | Identity and attribution |
| `billing_period` | `monthly` or `yearly` |
| `status` | `active`, `paused`, or `cancelled` |
| `next_billing_at` | Optional locally known renewal timestamp |

There is at most one subscription per purchase. Updating status tracks the platform's knowledge only; it does not execute an action at the merchant.

## Invariants

- Every human-managed query is scoped to the authenticated owner's ID.
- Every agent request derives the agent and owner from the opaque credential.
- An agent and assigned payment method must share the same owner.
- Each policy belongs to the same owner as its agent; an agent credential cannot read or mutate policies.
- Missing policy data, invalid threshold data, and threshold-currency mismatch require review.
- Automatic approval requires an active assigned payment method; without one the item remains proposed.
- Only an active assigned method can approve or execute a cart item.
- A local direct method is never selected by automatic approval; it requires a
  human-managed proposal approval with a fresh CVC.
- Stored direct-card PAN is encrypted and tenant scoped. CVC is never durable,
  is bound to one execution/owner/method in worker memory, and is consumed once
  within its TTL.
- Only the originating agent can record a legacy completion; managed completion
  belongs exclusively to the trusted worker.
- Final amount and currency must exactly equal the proposal.
- One managed execution exists per cart item and is created in the same
  transaction as approval.
- A worker revalidates tenant, agent, assignment, method state, adapter, URL,
  and the merchant-displayed product title, quantity, amount, and currency
  before retrieving a card and immediately before submission.
- Local direct form analysis is observe-only and completes before PAN/CVC
  retrieval; only validated selectors reach deterministic injection code.
- A managed checkout is retried only before `submitted_at`; ambiguous
  post-submit outcomes are never automatically retried.
- Every managed execution state change is appended transactionally to its
  tenant-scoped status history.
- Each managed execution emits at most one durable terminal event.
- One cart item creates at most one purchase; one purchase creates at most one subscription.
- Disabling a payment method removes its active assignments but does not erase history.
- Revoking an agent clears its authentication material but does not erase purchase history.
- Merchant passwords are encrypted and excluded from ordinary serializers.

## Money, URLs, and time

- Money is stored as `NUMERIC(18,2)` and represented as a fixed-precision decimal plus uppercase three-letter currency. Binary floating-point storage is prohibited.
- Two decimal places make the prototype appropriate for common fiat currencies but not every ISO currency. A production currency table or integer minor-unit model is required for zero- and three-decimal currencies.
- Product and login URLs are validated as absolute HTTP(S) URLs and are not
  fetched by FastAPI.
- A managed checkout URL must be HTTPS, use an operator-allowlisted public
  origin, and remain within the adapter's merchant/payment-frame origins.
- Merchant display identity remains a string; the execution authorization uses
  the normalized checkout origin instead.
- Persisted timestamps use timezone-aware UTC and APIs emit an explicit offset.

## Managed execution lifecycle

```mermaid
stateDiagram-v2
    [*] --> queued: approval commits execution
    queued --> running: worker claims lease
    running --> queued: retryable pre-submit failure
    running --> succeeded: rail-specific result proof accepted
    running --> failed: safe terminal failure or retry limit
    running --> action_required: challenge or user interaction
    running --> outcome_unknown: post-submit outcome cannot be proven
    running --> outcome_unknown: submitted lease expires
```

`outcome_unknown` is essential: automatically retrying an ambiguous checkout
can double charge the user. It has no automated outgoing transition. An
operator must reconcile merchant and issuer records before any separate retry
or corrective action.

For configured Stripe Issuing, success includes a matched issuer
authorization. For `local_direct_card`, success means only that the configured
merchant success marker and order reference were observed; it is not issuer
authorization, settlement, or clearing evidence. Both rails record
`submitted_at` before the first secret-field mutation and forbid automatic
post-boundary resubmission.

## Target supporting entities

- `IdempotencyRecord`: principal, endpoint, opaque key, canonical request hash, prior response, expiry.
- `CheckoutAttempt`: immutable per-attempt details and reconciliation evidence;
  status transitions are now retained, but DOM/provider evidence and detailed
  per-attempt timings are not.
- `OutboxEvent`: durable event written in the same transaction as business state, later published to Redis/another broker.
- `AuditEvent`: append-only actor, action, resource, result, correlation ID, redacted metadata, timestamp.
- `AgentChallenge`: single-use nonce and public key for proof-of-possession pairing.
- `MerchantAccount`: optional reusable merchant origin/email/secret reference, if reuse is intentionally supported.
