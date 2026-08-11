<p align="center">
  <img src="assets/agpay-mark.png" width="112" alt="AG Pay logo" />
</p>

# AG Pay

[![Status: Prototype](https://img.shields.io/badge/status-prototype-F59E0B?style=flat-square)](#what-we-are-building)
[![Autonomy: Human Supervised](https://img.shields.io/badge/autonomy-human_supervised-7C3AED?style=flat-square)](#what-we-are-building)
[![Security: No Raw Card Data](https://img.shields.io/badge/security-no_raw_card_data-0891B2?style=flat-square)](#what-we-are-building)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-16A34A?style=flat-square)](#help-build-the-payment-layer-for-agents)

![AI agents purchasing goods and digital services through AG Pay](assets/ag-pay-agent-commerce.png)

**A human-supervised payment control plane for AI agents.**

## Quick start

The public development workspace is made of independent repositories nested
under the base repository's ignored `dev/` directory. They are regular Git
repositories, not submodules.

### Tech stack

| Component | Technology |
| --- | --- |
| Platform API | Python 3.12, FastAPI, Pydantic, async SQLAlchemy, Alembic |
| Web application | Next.js 16, React 19, TypeScript, Tailwind CSS 4, shadcn/Radix, TanStack Query |
| Data and local infrastructure | PostgreSQL 16, Redis 7, pgAdmin, Docker Compose |
| OpenClaw plugin | TypeScript, TypeBox, OpenClaw 2026.7.1-2, Vitest, ESLint |
| OpenClaw playground | Docker Compose, pinned OpenClaw Gateway, packaged local AG Pay plugin |

The prototype is a supervised control plane with an opt-in managed-checkout
path. For an explicitly configured merchant adapter and Stripe Issuing virtual
card reference, approval queues a durable job; a trusted worker uses
Browserbase and deterministic Playwright automation without exposing card data
to OpenClaw or an LLM. Other proposals retain the legacy external-completion
flow. This narrow integration is not a universal or production-ready payment
processor.
For a complete visual sandbox run, the development-only `stripe-hosted` rail
creates a real Stripe test-mode Checkout Session from the approved product
facts, drives Stripe's official success/decline fixtures through Browserbase,
verifies the PaymentIntent through Stripe's API, and uses the same durable AG
Pay/OpenClaw outcome path. It does not order from the supplied product URL or
claim arbitrary production-merchant support; see
[Managed checkout](docs/managed-checkout.md).

### Prerequisites

- Git, a POSIX-like shell, and GNU or BSD Make;
- Docker Desktop or Docker Engine with Compose v2;
- Python 3.12 available as `python3.12`;
- Node.js 24.15.x and pnpm 11.9.0 for one toolchain that satisfies both the web
  application and OpenClaw plugin; and
- free local ports `3000`, `5050`, `5432`, `6379`, `8000`, and `18789`.

An OpenAI API key, or another model-provider configuration, is optional and is
needed only for actual model-backed OpenClaw turns. Never paste provider keys,
pairing tokens, agent tokens, or payment credentials into an agent chat.

### 1. Clone the base repository

```bash
git clone https://github.com/AG-Pay-Labs/ag-pay.git
cd ag-pay
```

### 2. Clone the nested repositories

```bash
mkdir -p dev
git clone https://github.com/AG-Pay-Labs/ag-pay-platform.git dev/ag-pay-platform
git clone https://github.com/AG-Pay-Labs/ag-plugin-openclaw.git dev/ag-plugin-openclaw
git clone https://github.com/AG-Pay-Labs/ag-openclaw-playground.git dev/ag-openclaw-playground
```

Keep these repositories independent. Do not add them to the base repository as
submodules or stage their files from the base repository.

### 3. Set up each repository

Run the following commands one at a time from the base repository root.

Start PostgreSQL, Redis, and pgAdmin:

```bash
make init-env
make infra-check
make infra-up
make infra-ps
```

Install and configure the platform:

```bash
cd dev/ag-pay-platform
make api-install
test -f .env || cp .env.example .env
make api-migrate
make web-install
test -f apps/web/.env.local || cp apps/web/.env.example apps/web/.env.local
cd ../..
```

Install and verify the OpenClaw plugin package. The plugin is a package loaded
by OpenClaw, not a standalone server:

```bash
cd dev/ag-plugin-openclaw
make install
make check
make pack-check
cd ../..
```

Start the API in one terminal:

```bash
cd dev/ag-pay-platform
make api-run
```

Start the web application in a second terminal:

```bash
cd dev/ag-pay-platform
make web-run
```

When managed checkout is configured, start its worker in a third terminal:

```bash
cd dev/ag-pay-platform
make checkout-worker
```

The local services are then available at:

- web application: `http://127.0.0.1:3000`;
- API documentation: `http://127.0.0.1:8000/docs`;
- API readiness: `http://127.0.0.1:8000/health/ready`; and
- pgAdmin: `http://127.0.0.1:5050`.

For the Stripe-hosted Browserbase proof, enable `CHECKOUT_ENABLED`,
`CHECKOUT_DEMO_ENABLED`, and `CHECKOUT_HOSTED_DEMO_ENABLED` in the platform's
untracked `.env`; provide only a Browserbase API key/project ID and Stripe
`sk_test_...` key; seed the fake demo methods with `make seed-checkout-demo
SEED_USERNAME=...`; and keep `make checkout-worker` running. The proof uses
Stripe's public hosted checkout, so it needs neither a local demo merchant nor
port `8100`. Follow the exact approval, decline/success, status-panel, and
OpenClaw verification steps in [Managed checkout](docs/managed-checkout.md#stripe-hosted-browserbase-proof-recommended).

### OpenClaw playground

The `dev/ag-openclaw-playground` repository builds the sibling
`dev/ag-plugin-openclaw` package into a pinned Dockerized OpenClaw runtime.
Keep the API running, then run:

```bash
cd dev/ag-openclaw-playground
make init
# Optional: add OPENAI_API_KEY to .env for model-backed turns.
make check
make smoke
make ps
make dashboard
```

Create an agent in the AG Pay web UI before running `make pair`; that command
accepts its one-time token at a hidden prompt. Run `make smoke` again afterward
to verify the Gateway, plugin, and SecretRef integration. The Control UI is at
`http://127.0.0.1:18789`. See the playground README for provider and Linux
networking details.

Stop the API and web processes with `Ctrl+C`. Run `make infra-down` from the
base repository and `make down` from `dev/ag-openclaw-playground` to stop all
Docker services without deleting their data.

### Set up with a coding agent

The canonical coding-agent workflow is in [`AGENTS.md`](AGENTS.md), with a
[`CLAUDE.md`](CLAUDE.md) entry point for Claude Code. From the base repository,
you can ask:

> Read AGENTS.md and follow its full local development bootstrap workflow. Set
> up every required repository, preserve existing files and secrets, run all
> documented health checks, and report anything that requires my input.

The agent will leave account registration, provider-key entry, and OpenClaw
pairing to you because those steps handle human or secret input.

## The vision

AI adoption is moving at extraordinary speed. Only a few years ago, many of us
were reluctant to accept a cookie banner. Today, we routinely invite AI into
our work, our ideas, and increasingly personal parts of our lives. For millions
of people, talking to an LLM has already become an everyday habit.

Yet even the most capable agent reaches a hard boundary when it needs to act in
the economy. It can research a product, compare providers, choose an API, or
recommend a subscription—but it cannot safely complete the next step on its
own. If agents are going to become genuinely useful collaborators, they need
more than intelligence. They need secure, accountable infrastructure for
economic action: buying goods, paying for APIs and services, managing
subscriptions, and requesting refunds.

We believe this missing payment layer should be designed around trust from the
beginning. Autonomy should be earned and configurable, important decisions
should remain visible, and people should always be able to understand which
agent spent what, where, and why.

## What we are building

AG Pay began as an experiment driven by curiosity: **what would a secure,
manageable wallet for AI agents actually look like?**

Giving an agent unrestricted access to a card is not an acceptable answer.
People need a way to set different rules for different agents, review sensitive
requests, share payment methods without losing accountability, and supervise
everything through an interface built for humans. Just as importantly, raw
card details must never be placed in an LLM prompt, context window, log, or
conversation.

AG Pay is exploring a control layer where:

- every agent has its own identity, permissions, and payment policy;
- cautious agents ask for approval while trusted agents can operate within
  narrower, explicitly defined rules;
- multiple agents can use the same approved payment method while every action
  remains attributable;
- humans can review proposals, approve or cancel them, and inspect purchase and
  subscription history in one place; and
- payment credentials stay behind provider boundaries, represented inside AG
  Pay only by safe references and non-sensitive metadata.

The current prototype deliberately starts with **supervised autonomy**. An agent
proposes a purchase and a human approves or cancels it. Configurable rules can
change how a proposal moves through AG Pay. A narrowly scoped managed path can
then execute an allowlisted checkout through Browserbase and Stripe Issuing;
the provider reference stays in AG Pay and raw payment fields exist only in the
trusted worker's memory. Unsupported merchants and payment providers remain on
the legacy external-result path. Broader live use still requires merchant
adapters, issuer controls, reconciliation, compliance review, and production
security hardening.

## Why open source

Payments, identity, and agent autonomy are too consequential to develop behind
closed doors. We want AG Pay to be a practical place for the open-source
community to explore the hard questions together: How much freedom should an
agent have? Where should approval be required? What should a trustworthy audit
trail contain? How can payment access be useful without exposing financial
secrets?

This project is early, and that is an invitation. Whether you work on agents,
payments, security, developer tools, product design, or simply share our
curiosity, you can help shape the protocols, safeguards, and user experience
that agent commerce will need.

## Help build the payment layer for agents

There are many ways to contribute. You can challenge the threat model, improve
the approval experience, propose policy primitives, explore payment-provider
integrations, strengthen tests and documentation, or bring an entirely new use
case. Thoughtful questions and well-reasoned criticism are as valuable at this
stage as code.

Start with the [project documentation](docs/README.md) to understand the
current scope and architecture. Then open an issue to share an idea, discuss a
design, or identify a gap. If you already know what you want to improve, a
focused pull request is welcome.
