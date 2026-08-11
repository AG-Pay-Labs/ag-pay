# Agent Wallet documentation

This directory is the source of truth for the first AG Pay agent-wallet prototype. The product is a control plane that lets a person connect software agents, assign approved payment methods, configure per-agent review rules, inspect purchase proposals, and retain an attributable history of purchases and subscriptions.

The first release defaults to **supervised autonomy**: every new agent starts with `always` review, so its proposals wait for a human. The owner can opt an agent into one of four narrower review modes. An approved proposal that names a server-configured checkout adapter is queued for a dedicated trusted worker; the worker supports the narrow Browserbase + Stripe Issuing flow documented here. Proposals without a managed adapter retain legacy external completion. The initial OpenClaw plugin adapts these agent endpoints and receives sanitized durable outcomes, while the Dockerized OpenClaw playground provides the local integration runtime. Universal merchant coverage, direct card issuance, issuer-enforced per-purchase limits, mobile clients, and a broader public developer SDK remain later phases.

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

The implemented prototype includes the FastAPI service, a responsive Next.js + shadcn management UI, a durable managed-checkout queue/worker, and the OpenClaw integration. The UI keeps the human bearer token in an HttpOnly same-site cookie and reaches FastAPI through an allowlisted backend-for-frontend route. The configured-merchant rail is deliberately limited to operator-owned adapter definitions and Stripe Issuing references. A distinct development-only `stripe-hosted` proof creates and verifies Stripe test-mode Checkout Sessions from approved facts so Browserbase success/decline and the complete status/notification path can be demonstrated without a local merchant; it is not arbitrary-site purchasing. Legacy completion remains available for sandbox compatibility. The API/domain documents distinguish these narrow implementations from production hardening such as signed pairing, provider-hosted card onboarding, webhooks and reconciliation, audited secret management, and issuer-enforced per-purchase virtual-card limits.
