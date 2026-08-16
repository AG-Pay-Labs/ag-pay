# Agent Wallet documentation

This directory is the source of truth for the first AG Pay agent-wallet prototype. The product is a control plane that lets a person connect software agents, assign approved payment methods, configure per-agent review rules, inspect purchase proposals, and retain an attributable history of purchases and subscriptions.

The first release defaults to **supervised autonomy**: every new agent starts with `always` review, so its proposals wait for a human. The owner can opt an agent into one of four narrower review modes. An approved proposal that names a server-configured checkout adapter is queued for a dedicated trusted worker; the worker supports the narrow Browserbase + Stripe Issuing flow and a development-only, US-only Stripe Link test flow documented here. For OpenClaw, every managed purchase call must explicitly supply its adapter and exact checkout URL; the plugin and playground do not inject defaults, and the tool rejects a missing or partial pair before contacting AG Pay. Older or direct API-created proposals without the pair remain legacy approval-only: human approval does not queue a worker or execute payment, and the item cannot be upgraded in place. The initial OpenClaw plugin adapts these agent endpoints and receives sanitized durable outcomes, while the Dockerized OpenClaw playground provides the local integration runtime. Universal merchant coverage, direct card issuance, issuer-enforced per-purchase limits, mobile clients, and a broader public developer SDK remain later phases.

## Document map

| Document | Purpose |
| --- | --- |
| [Product scope](./product-scope.md) | Goals, actors, use cases, MVP requirements, and non-goals |
| [System architecture](./architecture.md) | Next.js BFF, FastAPI, data services, trust boundaries, and key runtime flows |
| [Domain model](./domain-model.md) | Entities, relationships, lifecycle states, and invariants |
| [HTTP API](./api.md) | Implemented `0.1.0` endpoint inventory, payload examples, and known gaps |
| [Agent pairing and security](./agent-pairing-and-security.md) | Pairing handshake, agent authentication, authorization, and threat controls |
| [Payments and compliance](./payments-and-compliance.md) | Card-data boundary, tokenization, business billing data, and future card issuance |
| [Managed checkout](./managed-checkout.md) | Implemented Browserbase/Stripe worker, hosted test proof, security boundary, configuration, and sandbox procedures |
| [Stripe Link agent payments](./stripe-link-agent-payments.md) | Pinned Link CLI setup, owner-scoped authentication, and supervised hosted test procedure |
| [Repository and local development](./repository-and-local-development.md) | Multi-repository layout, platform/plugin/playground setup, Docker services, and developer workflow |
| [Operations](./operations.md) | Configuration, observability, backups, migrations, and incident basics |

## Terminology

- **Platform user**: the human who registers, owns agents, manages payment methods, and approves cart items.
- **Agent**: an OpenClaw-like autonomous process connected to the platform.
- **Agent pairing**: the one-time handshake that binds an agent installation to an agent record owned by a platform user.
- **Payment method**: a tokenized reference and display metadata for a card; never a stored raw card number or CVC.
- **Assignment**: the many-to-many authorization linking an agent to a payment method.
- **Payment policy**: the per-agent rule that decides whether a new proposal requires human review; `always` is the safety default.
- **Purchase credential**: the per-cart-item email/password identity used at a merchant so the human can later access that account.
- **Cart item**: the product, rationale, price, recurrence, and purchase credential proposed by an agent; it may remain proposed for review or become approved through the configured policy.
- **Checkout execution**: the durable job and safe outcome for a managed, allowlisted post-approval checkout.
- **Purchase**: the record created after managed checkout verification or legacy external completion of an approved cart item.
- **Subscription**: a recurring commitment created by a purchase, initially monthly or yearly.

## Status

The implemented prototype includes the FastAPI service, a responsive Next.js + shadcn management UI, a durable managed-checkout queue/worker, and the OpenClaw integration. The UI keeps the human bearer token in an HttpOnly same-site cookie and reaches FastAPI through an allowlisted backend-for-frontend route. The configured-merchant rail is deliberately limited to operator-owned adapter definitions and Stripe Issuing references. A distinct development-only `stripe-hosted` proof opens an exact, offer-specific Stripe test Checkout Session URL supplied explicitly with the proposal, fills it through Browserbase, and accepts success only from a server-verified receipt on the allowlisted `letyouragentspay.com` landing site. Stripe credentials stay on that landing server; the worker does not create or poll a Checkout Session and does not need `STRIPE_DEMO_SECRET_KEY`. A single fixed URL represents one fixed offer, so each OpenClaw managed purchase call must supply the URL matching that offer together with `stripe-hosted`; neither integration layer adds it later. This demonstrates Browserbase success and the complete status/notification path without a local merchant; it is not arbitrary-site purchasing. Legacy completion remains available for sandbox compatibility, but approving a legacy item does not execute payment. The API/domain documents distinguish these narrow implementations from production hardening such as signed pairing, provider-hosted card onboarding, webhooks and reconciliation, audited secret management, and issuer-enforced per-purchase virtual-card limits.
