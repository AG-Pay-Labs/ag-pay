# Payments and compliance boundary

## Non-negotiable card-data boundary

The Agent Wallet backend must not receive, persist, log, cache, or return raw card numbers (PAN), CVC/CVV, PIN data, magnetic-stripe data, or 3-D Secure authentication secrets.

For a production integration, “add a card” therefore means:

1. The web/mobile client renders payment-provider-hosted fields or redirects to a provider-hosted setup flow.
2. Card details travel directly from the client to the compliant provider.
3. The provider returns a setup token or payment-method reference.
4. The client sends only that opaque reference to Agent Wallet.
5. The backend stores safe metadata: brand, last four digits, expiration, and personal/business billing details. The prototype accepts that safe metadata from the client; a live provider adapter must resolve and verify it server-side.

The web application accepts only an opaque provider reference and safe display metadata; it deliberately has no PAN or CVC field. The managed worker currently recognizes only an explicitly configured `stripe_issuing` reference (`ic_...`) and revalidates it with Stripe at execution time. Sandbox references remain useful for the legacy test flow. The root Docker Compose PostgreSQL instance is never an acceptable card vault.

## Why tokenization is required

Collecting raw card details would materially expand PCI DSS scope and create a high-impact credential store. CVC storage after authorization is prohibited by card-industry rules, even if encrypted. Generic “encrypt the card in PostgreSQL” designs do not create a safe or sufficient payment architecture.

Using provider-hosted collection reduces exposure but does not eliminate all compliance obligations. Before handling real payments, the company must confirm the exact integration, merchant-of-record model, applicable PCI self-assessment, privacy duties, regional payment authentication, and agent/card-network program rules with qualified legal and compliance specialists.

This document is architectural guidance, not a compliance certification or legal opinion.

## What the backend may store

### Payment method

- provider name and opaque payment-method/issuer reference;
- brand/network and funding type when supplied;
- last four digits;
- expiration month/year;
- provider fingerprint when a future provider adapter supplies it;
- embedded personal or business billing details in the prototype, or a reusable billing-profile ID in a later normalized schema;
- status and timestamps.

Provider references should be treated as sensitive: omit them from normal responses and logs, restrict database access, and encrypt them if provider guidance or the threat model warrants it.

### Personal billing details

- cardholder/contact name;
- address lines, city, region, postal code, country;
- optional phone/email only when a provider or merchant flow needs them.

### Business billing details

- legal entity name and trading name;
- registered and/or billing address;
- company registration number;
- normalized VAT/tax identifier and tax country;
- tax-ID verification status and evidence timestamp when verification is implemented;
- authorized billing contact.

Billing and tax data is personal/confidential information even when it is not card data. Apply access controls, retention limits, audit logging, encryption at rest, and privacy processes.

## What an agent receives

The control plane does not expose raw card credentials. The agent API receives the selected payment-method UUID and a safe managed-execution status, along with the exact proposed amount/currency and recurrence. It does not receive raw card fields, Browserbase connection/session data, merchant passwords, provider references, or provider authorizations. OpenClaw receives only a fixed plugin-owned summary from the durable terminal event.

A later provider-mediated integration may additionally give a narrowly authorized runtime:

- a safe payment-method label;
- the approval's merchant, currency, and amount bounds;
- a short-lived execution/payment authorization from a provider or issuer, if supported;
- a request-scoped merchant-account credential lease, if required.

A token created merely to store a card with a PSP is usually not a credential accepted by an arbitrary merchant checkout. The implemented managed path therefore supports only Stripe Issuing virtual-card references and server-owned, allowlisted merchant adapters. Unknown merchants or providers fail closed; no generic LLM decides where payment secrets are entered.

## Production execution strategies

### Preferred: issuer-backed virtual cards

Use an issuing partner to create a virtual card per agent or per approved purchase. Set server-side constraints such as amount, currency, merchant/category, validity window, and recurrence. Reveal credentials only to the authorized agent for the shortest possible time, or inject them through a hardened execution environment.

Per-purchase virtual cards offer the clearest binding between a human approval and one spend event. Per-agent cards are more convenient but require stronger cumulative limits and monitoring.

### Provider-mediated merchant payment

Where the merchant is integrated with the same PSP, the backend can create a payment intent or equivalent without exposing credentials to the agent. This is safer but does not support arbitrary web merchants.

### Implemented narrow path: Browserbase credential injection

The dedicated worker can inject a Stripe Issuing virtual card into a configured merchant form without returning the secret to the language model. It requires provider-owned `agpay_owner_id` metadata to bind the card to the execution tenant, uses deterministic Playwright selectors from an operator-owned adapter snapshot, validates top-level and payment-frame origins, blocks unapproved HTTP and WebSocket egress and service workers, disables Browserbase recording/logging/CAPTCHA solving, and never persists a browser context. Raw number/CVC values live only in a repr-hidden in-memory object between issuer retrieval and form fill. Provider credentials must be injected only into the worker process in deployments; a shared local `.env` is a development convenience, not a production isolation boundary.

This integration brings the worker and Browserbase relationship into PCI and security scope. Browserbase Live View may still exist even when recording is disabled; access to that account must be tightly restricted and a production launch requires contractual zero-data-retention review. Stripe recommends Issuing Elements where possible and warns that API retrieval of virtual-card details expands PCI obligations. A compromised allowlisted merchant page necessarily sees the values entered into its own payment form, so origin allowlisting and reviewed adapter code—not prompt filtering—are the primary exfiltration controls.

The current adapter binds normalized title, quantity, and exact total, not a
merchant-issued immutable SKU or variant. Test adapters must therefore use
unique titles; immutable product/variant binding is a launch gate for non-test
money.

The worker serializes a card across executions and quarantines it after an
interactive or ambiguous outcome, preventing a late issuer authorization from
being attributed to a later request. Prefer a dedicated one-execution virtual
card anyway; unrelated external use of the same card is outside AG Pay's lock.

## Approval and recurring payments

The prototype stores a per-agent review policy. `always` is the default; the other modes can require review only for subscriptions, only when total amount is strictly above a same-currency threshold, for either condition, or never. The threshold is applied to `unit_price × quantity`, and equality does not trigger review. AG Pay does not perform currency conversion: a different proposal currency fails safe to human review.

When review is required, the human selects an active assigned payment method for the cart item's exact proposed amount/currency. When review is not required, the backend can mark the item approved only if it can select an active method already assigned to that agent; otherwise the item remains proposed. Completion rechecks the assignment and exact amount/currency in either case.

These review modes are control-plane workflow choices for legacy proposals,
not issuer-enforced spend limits. `never` can skip review only for an unmanaged
proposal; every managed checkout still requires explicit human approval.
Managed execution freezes the adapter, checkout origin, exact amount/currency,
human-selected method, and attempt state, but is currently limited to one-time
purchases; recurring proposals stay on the legacy test path because renewal
terms are not verified. The current policy still lacks aggregate budgets,
approval expiry, merchant/category issuer controls, and per-purchase
virtual-card issuance.

Before broader real payments, every human decision must become a bounded
execution grant containing an issuer-enforced amount ceiling, currency,
canonical merchant origin, payment method, recurrence terms, expiry, and
attempt limit. A one-time approval must never silently become a subscription.
Any future policy-derived execution would require separate risk/compliance
review, step-up controls, durable audit, and explicit user communication.

For a monthly or yearly subscription that requires review, display at approval time:

- initial charge and expected recurring amount;
- period and any trial period;
- merchant identity;
- known renewal date;
- cancellation method when available.

Automatically approved recurring proposals remain visible in the Approved queue so the owner can inspect them before or after the agent acts, but visibility is not a substitute for a production notification or revocation window. The platform tracks subscription metadata but should not state that a merchant subscription is cancelled until external cancellation is confirmed.

## Webhooks and reconciliation

Provider webhooks are not implemented. The worker correlates the merchant confirmation with a matching Stripe Issuing authorization fetched after submission, but that is not settlement reconciliation. A future webhook endpoint must verify the raw body using the provider's current signature procedure. Processing must be idempotent by provider event ID. Webhook input remains untrusted even after signature verification: validate schemas, tolerate out-of-order events, and reconcile against provider APIs when necessary.

Purchase history can contain both managed, provider-correlated outcomes and legacy agent-reported sandbox completions. A production record must continue to distinguish:

- agent-reported merchant success;
- provider-authorized/settled status;
- failed or unknown outcome.

Do not treat a client response alone as final settlement. A production system needs periodic reconciliation and explicit handling for timeouts where the merchant may have completed a charge.

## Logging and data handling

- Use allowlisted structured fields, not arbitrary request/response body logging.
- Redact authorization headers, cookies, pairing codes, merchant passwords, provider secrets, and fields resembling PAN/CVC.
- Do not place secrets in URLs, query strings, Redis pub/sub messages, error reports, analytics, or support screenshots.
- Use TLS for all non-local traffic and authenticated/encrypted connections to managed data stores.
- Restrict and audit access to production data and backups.
- Establish retention/deletion rules before onboarding real users.

## Prototype rule

Use Stripe test mode and a public sandbox merchant until the provider, Browserbase, issuer, security, legal, and compliance gates are complete. Never paste a real card number into API requests, `.env` files, database seed data, tests, issue trackers, or agent prompts. Even in a live pilot, configure only an opaque `ic_...` reference; the worker retrieves the virtual-card fields directly from Stripe.

The local demo's “Qonto Virtual Card” name, Mastercard brand, expiry, and ending digits are fabricated safe metadata for interface testing. They do not represent a Qonto account, usable card, provider authorization, or endorsement.
