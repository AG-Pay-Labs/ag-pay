# Agent Wallet documentation

This directory is the source of truth for the first AG Pay agent-wallet prototype. The product is a control plane that lets a person connect software agents, assign approved payment methods, configure per-agent review rules, inspect purchase proposals, and retain an attributable history of purchases and subscriptions.

The first release defaults to **supervised autonomy**: every new agent starts
with `always` review, so its proposals wait for a human. The owner can opt an
agent into four narrower review modes. An approved proposal naming a configured
adapter is queued for the trusted worker; implemented paths include narrow
Browserbase + Stripe Issuing, development-only Stripe/Link proofs, and a
disabled-by-default local direct-card research rail. The last stores encrypted
PAN, accepts CVC only with human approval into worker memory, and combines
observe-only selector mapping with deterministic injection. Every OpenClaw
managed call must still supply its exact adapter/URL. Legacy items without the
pair queue no payment. Universal merchant coverage, production local card
storage, issuer-enforced limits, mobile clients, and a broader SDK remain out of
scope or later phases.

## Document map

| Document | Purpose |
| --- | --- |
| [Product scope](./product-scope.md) | Goals, actors, use cases, MVP requirements, and non-goals |
| [System architecture](./architecture.md) | Next.js BFF, FastAPI, data services, trust boundaries, and key runtime flows |
| [Domain model](./domain-model.md) | Entities, relationships, lifecycle states, and invariants |
| [HTTP API](./api.md) | Implemented `0.1.0` endpoint inventory, payload examples, and known gaps |
| [Agent pairing and security](./agent-pairing-and-security.md) | Pairing handshake, agent authentication, authorization, and threat controls |
| [Managed checkout](./managed-checkout.md) | Canonical Browserbase/Stripe and local direct-card credential boundaries, adapter constraints, state machine, and failure rules |
| [Stripe Link agent payments](./stripe-link-agent-payments.md) | Pinned Link CLI setup, owner-scoped authentication, and supervised hosted test procedure |
| [Repository and local development](./repository-and-local-development.md) | Full multi-repository setup, Docker services, OpenClaw workflow, Stripe-hosted proof, and no-charge local card procedure |
| [Operations](./operations.md) | Configuration, observability, backups, migrations, and incident basics |

## Terminology

- **Platform user**: the human who registers, owns agents, manages payment methods, and approves cart items.
- **Agent**: an OpenClaw-like autonomous process connected to the platform.
- **Agent pairing**: the one-time handshake that binds an agent installation to an agent record owned by a platform user.
- **Payment method**: a provider/local opaque reference and safe card metadata.
  A development/test-only local method may have a separate owner-scoped
  encrypted-PAN row; CVC is never durable.
- **Assignment**: the many-to-many authorization linking an agent to a payment method.
- **Payment policy**: the per-agent rule that decides whether a new proposal requires human review; `always` is the safety default.
- **Purchase credential**: the per-cart-item email/password identity used at a merchant so the human can later access that account.
- **Cart item**: the product, rationale, price, recurrence, and purchase credential proposed by an agent; it may remain proposed for review or become approved through the configured policy.
- **Checkout execution**: the durable job and safe outcome for a managed, allowlisted post-approval checkout.
- **Purchase**: the record created after managed checkout verification or legacy external completion of an approved cart item.
- **Subscription**: a recurring commitment created by a purchase, initially monthly or yearly.

## Status

The implemented prototype includes FastAPI, the responsive management UI, a
durable checkout queue/worker, and OpenClaw integration. The configured rail is
limited to operator-owned adapters and Stripe Issuing references. The
development-only `stripe-hosted` proof uses an exact offer-specific Stripe test
URL and server-verified landing receipt. The separate `local_direct_card`
experiment stores tenant-scoped encrypted PAN and accepts CVC only at human
approval through the worker's private, one-shot memory broker. Stagehand
observes empty controls only; validated selectors are frozen and deterministic
JavaScript/Playwright performs actions. Its merchant-page result is not issuer
authorization. These paths do not establish arbitrary-site or production
support; legacy approval still executes nothing.

## Delivery roadmap

| Phase | Status | Scope |
| --- | --- | --- |
| Stripe Playground | Implemented for development | Supervised Stripe test checkout through Browserbase, with a server-verified receipt and durable AG Pay/OpenClaw outcome |
| Local direct-card research | Implemented for development/test only | Encrypted PAN, approval-time worker-memory CVC, observe-only mapping, and deterministic injection for explicit adapters; no issuer-result claim |
| Hardened direct form injection | Next | Reviewed, allowlisted merchant adapters inject provider-issued, short-lived credentials from trusted-worker memory without exposing them to the model or control plane |
| Visa and Mastercard payment networks | Planned | Provider-hosted enrollment, authenticated bounded payment instructions, safe credential delivery, network controls, and outcome signals, subject to each network's access, onboarding, certification, availability, and compliance requirements |
| Broader ecosystem | Later | Additional issuers, wallets, PSPs, merchant APIs, and agent platforms through provider-neutral adapters |

The existing configured-merchant worker and local research rail prove
deliberately narrow injection paths. The next phase broadens and hardens the
provider-issued model;
it does not turn arbitrary merchant pages into trusted checkout adapters.
Visa, Mastercard, and other ecosystem entries are roadmap targets only and do
not imply current integration, approval, endorsement, or production support.
