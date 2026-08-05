# Agent Wallet documentation

This directory is the source of truth for the first AG Pay agent-wallet prototype. The product is a control plane that lets a person connect software agents, assign approved payment methods, configure per-agent review rules, inspect purchase proposals, and retain an attributable history of purchases and subscriptions.

The first release defaults to **supervised autonomy**: every new agent starts with `always` review, so its proposals wait for a human. The owner can opt an agent into one of four narrower review modes. A server-side automatic decision marks a proposal approved only when an active assigned payment method exists; it does not execute or authorize a real payment. The initial OpenClaw plugin adapts these agent endpoints; live payment execution, direct card issuance, issuer-enforced limits, mobile clients, and a broader public developer SDK are later phases.

## Document map

| Document | Purpose |
| --- | --- |
| [Product scope](./product-scope.md) | Goals, actors, use cases, MVP requirements, and non-goals |
| [System architecture](./architecture.md) | Next.js BFF, FastAPI, data services, trust boundaries, and key runtime flows |
| [Domain model](./domain-model.md) | Entities, relationships, lifecycle states, and invariants |
| [HTTP API](./api.md) | Implemented `0.1.0` endpoint inventory, payload examples, and known gaps |
| [Agent pairing and security](./agent-pairing-and-security.md) | Pairing handshake, agent authentication, authorization, and threat controls |
| [Payments and compliance](./payments-and-compliance.md) | Card-data boundary, tokenization, business billing data, and future card issuance |
| [Repository and local development](./repository-and-local-development.md) | Multi-repository layout, Docker services, setup, and developer workflow |
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
- **Purchase**: the record created when an agent reports successful completion of an approved cart item.
- **Subscription**: a recurring commitment created by a purchase, initially monthly or yearly.

## Status

The implemented prototype includes the FastAPI service and a responsive Next.js + shadcn management UI with polished runtime cards, safe masked virtual-card views, approval queues, and a per-agent Rules page. The UI keeps the human bearer token in an HttpOnly same-site cookie and reaches FastAPI through an allowlisted backend-for-frontend route. The API/domain documents distinguish implemented `0.1.0` behavior from production hardening. Architecture recommendations such as signed pairing, hosted provider card collection, execution leases, durable audit/outbox records, and issuer-backed virtual cards are explicitly marked as future work.
