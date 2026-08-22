# Repository and local development

## Repository model

The project uses a lightweight base repository plus independently versioned development repositories nested under the ignored `dev/` directory.

```text
ag-pay/                         # base repository
├── .env.example               # local infrastructure defaults
├── .gitignore                 # ignores .env and nested dev repositories
├── Makefile                   # infrastructure shortcuts
├── AGENTS.md                  # development-agent boundaries and guardrails
├── docker-compose.yml         # PostgreSQL, Redis, pgAdmin
├── docs/                      # product and architecture source of truth
└── dev/                       # ignored workspace for separate repositories
    ├── ag-pay-platform/       # current FastAPI + Next.js monorepo
    ├── mobile/                # future mobile repository
    ├── ag-plugin-openclaw/    # OpenClaw plugin repository
    └── ag-openclaw-playground/ # Dockerized OpenClaw + AG Pay plugin playground
```

`dev/` is not a Git submodule. Each child repository owns its own history, CI, releases, dependencies, and secrets. The base repository owns cross-project documentation and local shared infrastructure. The current `dev/ag-pay-platform` contents remain ignored by the base Git repository as intended.

## Clone the public workspace

```bash
git clone https://github.com/AG-Pay-Labs/ag-pay.git
cd ag-pay
mkdir -p dev
git clone https://github.com/AG-Pay-Labs/ag-pay-platform.git dev/ag-pay-platform
git clone https://github.com/AG-Pay-Labs/ag-plugin-openclaw.git dev/ag-plugin-openclaw
git clone https://github.com/AG-Pay-Labs/ag-openclaw-playground.git dev/ag-openclaw-playground
```

The future `mobile` repository does not yet have a confirmed public clone URL.
Do not invent one; add its canonical clone command only when it is published.

## Current `ag-pay-platform` layout

```text
dev/ag-pay-platform/
├── .env.example
├── AGENTS.md
├── Makefile
├── README.md
└── apps/
    ├── api/
    │   ├── migrations/                # Alembic environment and revisions
    │   ├── src/ag_platform_api/
    │   │   ├── api/                   # routers and auth dependencies
    │   │   ├── core/                  # settings and security primitives
    │   │   ├── db/                    # async engine/session/base
    │   │   ├── services/              # Redis broker and serializers
    │   │   ├── main.py                # FastAPI application
    │   │   ├── models.py              # SQLAlchemy models
    │   │   └── schemas.py             # Pydantic API models
    │   ├── scripts/seed_demo_data.py  # idempotent fake demonstration data
    │   ├── tests/
    │   ├── alembic.ini
    │   └── pyproject.toml
    └── web/
        ├── src/app/                   # App Router pages and BFF route handlers
        ├── src/components/            # shadcn primitives and product UI
        ├── src/hooks/                 # TanStack Query resource hooks
        ├── src/lib/                   # browser API client, types, server session/proxy
        ├── components.json            # shadcn configuration
        ├── package.json
        └── pnpm-lock.yaml
```

The API is one modular service. The web app is a separate Next.js process that acts as the browser UI and human-session BFF. As the API grows, split the large model/schema modules by domain while keeping imports and Alembic metadata explicit.

## Prerequisites

- Git
- Docker with Compose v2
- GNU/BSD Make for the root shortcuts
- Python 3.12 (the package accepts Python `>=3.12,<3.14`)
- Node.js 24.15.x and pnpm 11.9.0 are the recommended shared toolchain for the
  web application and OpenClaw plugin
- Docker builds the playground's pinned OpenClaw/Node runtime; no compatible
  host Node.js installation is required for that subproject
- A POSIX-like shell for the examples
- Free local ports `3000`, `5050`, `5432`, `6379`, `8000`, and `18789`; the
  optional no-charge direct-card fixture also uses `8101`

## Start local infrastructure

From the base repository root:

```bash
make init-env
make infra-check
make infra-up
make infra-ps
```

`make init-env` copies the root `.env.example` only when `.env` does not already exist. The Compose services bind to loopback by default:

- PostgreSQL: `127.0.0.1:5432`
- Redis: `127.0.0.1:6379`
- pgAdmin: `http://127.0.0.1:5050`

The Compose defaults are local-development credentials, not secrets suitable for shared environments.

## Configure and run the API

From the base repository:

```bash
cd dev/ag-pay-platform/apps/api
python3.12 -m venv .venv
.venv/bin/python -m pip install -e '.[dev]'
test -f ../../.env || cp ../../.env.example ../../.env
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m uvicorn ag_platform_api.main:app --reload
```

The copy command creates `dev/ag-pay-platform/.env`, which the API settings load from `../../.env` when launched from `apps/api`. If that file already contains local configuration, do not overwrite it; compare it with `.env.example` and merge intentionally.

The development API is then available at:

- OpenAPI UI: `http://127.0.0.1:8000/docs`
- liveness: `http://127.0.0.1:8000/health/live`
- readiness: `http://127.0.0.1:8000/health/ready`

## Configure and run the web app

Keep the API running, then use another terminal:

```bash
cd dev/ag-pay-platform
make web-install
test -f apps/web/.env.local || cp apps/web/.env.example apps/web/.env.local
make web-run
```

Open `http://127.0.0.1:3000`. `AGPAY_API_URL` is a server-only setting and defaults to `http://localhost:8000`; set it to the reachable FastAPI origin when the processes are deployed differently. Do not rename it with a `NEXT_PUBLIC_` prefix because the browser must not receive backend credentials or bypass the BFF.

The browser uses same-origin auth and proxy routes. Login/registration place the FastAPI JWT in an HttpOnly, same-site cookie. The BFF adds that token to allowlisted human API calls and uses `Cache-Control: no-store`, including for merchant-credential reveal. Agent handshake, heartbeat, proposal, and completion endpoints are intentionally not present in the browser proxy.

## Run the Stripe-hosted checkout proof

In the platform's untracked `.env`, set `CHECKOUT_ENABLED=true`,
`CHECKOUT_DEMO_ENABLED=true`, and `CHECKOUT_HOSTED_DEMO_ENABLED=true`, then add
the Browserbase API key/project ID. Do not set `STRIPE_DEMO_SECRET_KEY` for this
rail: the `letyouragentspay.com` landing server owns the Stripe test credential
and server-verifies the redirected session. Start `make checkout-worker` in a
separate platform terminal. After creating the human account and agent, run
`make seed-checkout-demo SEED_USERNAME=...` to add and assign the safe success,
decline, and 3DS fixture references. On the keyless fixed-URL rail, only the
server-verified success fixture can become `succeeded`; a submitted decline or
3DS flow becomes `outcome_unknown` for manual reconciliation.

The proposal must supply the exact offer-specific full
`https://checkout.stripe.com/c/pay/cs_test_...#...` URL, including its
fragment; the generic Stripe root is not sufficient, and one fixed URL cannot
represent multiple offers. Pass `checkout_adapter=stripe-hosted` and that URL
explicitly in every OpenClaw managed purchase tool call; do not configure a
checkout default in the plugin or playground. The worker opens that existing
URL after approval and accepts only the matching verified landing receipt. The
OpenClaw tool rejects a missing or partial pair before contacting AG Pay. Older
or direct API-created legacy items queue no payment when approved and cannot be
upgraded; submit a fresh managed request. This mode does not need the local demo
merchant, an HTTPS tunnel, or port `8100`. It tests the AG Pay status and
OpenClaw outcome loop; it does not create an order at the proposal's source
product URL. Follow the full procedure and expected evidence in [Managed checkout](./managed-checkout.md#stripe-hosted-browserbase-proof-recommended).

## Run the local direct-card no-charge fixture

This optional path is for controlled `development`/`test` research only. It
exercises encrypted PAN storage, approval-time one-shot CVC handoff,
observe-only form mapping, deterministic browser filling, and durable AG Pay
outcomes. The built-in fixture does not contact a processor or charge a card.
Never enter a live card, expose another local service through the tunnel, or
treat fixture success as issuer authorization.

Complete the core infrastructure, API, and web setup above first. You also need
a Browserbase project/API key and a trusted HTTPS tunnel that can expose only
the fixture on `127.0.0.1:8101`.

### 1. Generate independent local secrets

From the base repository, generate a dedicated Fernet key and a separate
random broker token:

```bash
cd dev/ag-pay-platform
apps/api/.venv/bin/python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
apps/api/.venv/bin/python -c 'import secrets; print(secrets.token_urlsafe(32))'
```

Copy both outputs only into the untracked platform `.env`. Do not reuse the
JWT key, merchant-credential encryption key, Gateway token, or another
application secret. Never paste either generated value into chat, logs, source
control, or a command argument.

### 2. Start and expose the no-charge fixture

In a separate terminal:

```bash
cd dev/ag-pay-platform
make direct-card-fixture-run
```

The fixture is now at `http://127.0.0.1:8101/checkout`. Start a trusted HTTPS
tunnel to local port `8101` and record its exact public origin, for example
`https://YOUR-FIXTURE-HOST`. Expose only `8101`: never tunnel the AG Pay API,
PostgreSQL, Redis, pgAdmin, or OpenClaw. Keep the fixture and tunnel running for
the test. Confirm the public route before configuring the adapter:

```bash
curl -fsS https://YOUR-FIXTURE-HOST/health/live
curl -fsS https://YOUR-FIXTURE-HOST/checkout >/dev/null
```

### 3. Enable the rail and configure its explicit adapter

Preserve the existing database, Redis, authentication, and Browserbase values
in `dev/ag-pay-platform/.env`, then add or update these keys. Replace the two
generated-value placeholders and every `YOUR-FIXTURE-HOST` occurrence:

```dotenv
ENVIRONMENT=development
CHECKOUT_ENABLED=true
LOCAL_DIRECT_CARD_ENABLED=true
DIRECT_CARD_ENCRYPTION_KEY=PASTE_DEDICATED_FERNET_KEY
LOCAL_DIRECT_CARD_BROKER_TOKEN=PASTE_SEPARATE_RANDOM_TOKEN
LOCAL_DIRECT_CARD_SOCKET_PATH=/tmp/agpay-direct-card/cvc.sock
LOCAL_DIRECT_CARD_CVC_TTL_SECONDS=300
LOCAL_DIRECT_CARD_SOCKET_TIMEOUT_SECONDS=2
CHECKOUT_FORM_ANALYSIS_MODEL=google/gemini-2.5-flash
CHECKOUT_FORM_ANALYSIS_TIMEOUT_SECONDS=120
BROWSERBASE_API_KEY=your_private_browserbase_key
BROWSERBASE_PROJECT_ID=your_private_browserbase_project_id
CHECKOUT_ADAPTERS={"direct-card-fixture":{"allowed_origins":["https://YOUR-FIXTURE-HOST"],"payment_origins":["https://YOUR-FIXTURE-HOST"],"checkout_mode":"direct","payment_form_strategy":"browserbase_ai","product_title_selector":"#research-product-title","quantity_selector":"#research-quantity","total_selector":"#research-total","success_selector":"#research-success:not([hidden])","order_reference_selector":"#research-order-reference"}}
```

Use the origin only in `allowed_origins` and `payment_origins`; `/checkout`
belongs only in the proposal URL. Keep `CHECKOUT_ADAPTERS` as one JSON object.
If the `.env` already contains adapters, merge `direct-card-fixture` into that
object instead of adding a second environment line or discarding other
adapters. The direct adapter intentionally omits card, expiry, billing, CVC,
and submit selectors so Stagehand must observe the empty form before the worker
loads any card value.

### 4. Restart the API and start the worker

Settings load at process startup. Stop an already running API or worker with
`Ctrl+C`, run migrations, then start each process in its own terminal:

```bash
cd dev/ag-pay-platform
make api-migrate
make api-run
```

```bash
cd dev/ag-pay-platform
make checkout-worker
```

Keep `make web-run`, `make direct-card-fixture-run`, the HTTPS tunnel, and the
checkout worker running. The worker creates the private socket directory and
socket; startup fails closed unless their ownership and modes establish the
required private boundary. The worker must be healthy before approval because
the API hands CVC directly to its short-lived, one-shot memory broker.

Verify the API after restart:

```bash
curl -fsS http://127.0.0.1:8000/health/live
curl -fsS http://127.0.0.1:8000/health/ready
```

### 5. Enroll and assign a synthetic card

1. Open `http://127.0.0.1:3000`, register or log in, and create an agent.
2. In **Cards**, choose the local direct-card form.
3. Enter only a Luhn-valid synthetic/test PAN, expiry, safe billing details,
   and a display name. Enrollment must not ask for or accept CVC.
4. Assign the returned local method to the agent that will create the proposal.

The normal card response exposes only safe metadata and an opaque `ldc_...`
reference. The dedicated encrypted credential row stores PAN ciphertext; CVC
is never written to PostgreSQL, Redis, a file, event, or log.

### 6. Create and approve one exact managed proposal

Use the paired OpenClaw agent or agent API to create a fresh one-time proposal
with these exact fixture facts:

| Field | Value |
| --- | --- |
| Checkout adapter | `direct-card-fixture` |
| Checkout URL | `https://YOUR-FIXTURE-HOST/checkout` |
| Title | `AG Pay direct-card research fixture` |
| Quantity | `1` |
| Unit price | `25.00` |
| Currency | `EUR` |
| Billing period | none / one-time |

Local direct methods are never automatically selected or approved. In the AG
Pay approval dialog, inspect the frozen product facts, explicitly select the
assigned local method, enter a three- or four-digit test CVC, and approve once.
CVC expires after the configured TTL and is consumed exactly once.

### 7. Verify the result and stop safely

The expected execution path is `queued -> running -> succeeded`, with a
`fixture-...` merchant order reference and one local research purchase record.
This verifies AG Pay's local handoff and browser workflow only; it proves no
authorization, processor interaction, charge, settlement, or arbitrary-site
compatibility.

If any error occurs after the first possible card fill, AG Pay records
`outcome_unknown`. Do not approve or submit the same proposal again. Investigate
the status, then create a new proposal only after confirming that the fixture
did not submit. Stop immediately if a non-fixture page introduces CAPTCHA, 3-D
Secure, a new origin/frame, ambiguous controls, changed product facts, or an
unreconcilable result.

Stop the API, web app, fixture, worker, and tunnel with `Ctrl+C`. Stop shared
services without deleting data:

```bash
cd dev/ag-openclaw-playground
make down

cd ../..
make infra-down
```

For the detailed credential boundary, adapter constraints, state machine, and
failure contract, read [Managed checkout — Local direct-card research
procedure](./managed-checkout.md#local-direct-card-research-procedure).

## Run the OpenClaw playground

Keep the API running, then start the independently versioned playground:

```bash
cd dev/ag-openclaw-playground
make init
# Add OPENAI_API_KEY to .env for model-backed agent turns.
make check
make smoke
make ps
make dashboard
```

The image pins a compatible OpenClaw release, builds and packs the sibling
`../ag-plugin-openclaw` source, installs it through OpenClaw's managed package
path, and waits for Gateway readiness. The published Gateway port is restricted
to host loopback. On Docker Desktop, a container-local loopback bridge forwards
plugin calls to the host API without weakening the plugin rule that plain HTTP
is accepted only on loopback.

On native Linux, a host API bound only to `127.0.0.1` is usually unreachable
through Docker's host-gateway address. Bind the API to a carefully firewalled,
container-reachable host interface for local development, or disable the bridge
and configure an HTTPS `AGPAY_API_URL` as described in the playground README.

After creating an OpenClaw agent in the human web app, run `make pair` and enter
the one-time pairing token at the hidden prompt. The resulting bearer token is
stored as a private file-backed OpenClaw SecretRef. Use `make smoke` to verify
the live plugin runtime, SecretRefs, and Gateway RPC. The plugin requests
supervised approval and monitors sanitized managed-checkout outcomes; it never
receives Browserbase, issuer, or card-field secrets. Managed execution belongs
to the separately configured platform worker, and playground smoke does not
initiate or prove a purchase.

Open the Control UI at `http://127.0.0.1:18789`. Run `make down` from the
playground repository to stop its containers without deleting OpenClaw state.

## Run API checks

From `dev/ag-pay-platform/apps/api` with the virtual environment installed:

```bash
.venv/bin/python -m ruff check .
.venv/bin/python -m pytest
```

For a fresh schema smoke test, start PostgreSQL and run:

```bash
.venv/bin/python -m alembic upgrade head
.venv/bin/python -m alembic current
```

Tests may use SQLite for fast isolated coverage, but PostgreSQL integration tests remain necessary for row-locking, JSON, constraints, and async-driver behavior.

## Run web checks

From `dev/ag-pay-platform`, use the Make targets:

```bash
make web-lint
make web-typecheck
make web-build
```

`make lint` combines the backend format/lint checks with web lint and
type-checking. The equivalent commands can be run directly from `apps/web`
with `pnpm lint`, `pnpm exec tsc --noEmit`, and `pnpm build`.

Run the production build with `AGPAY_API_URL` set for the deployment environment. Browser smoke tests should cover authentication redirects, responsive navigation, an agent pairing/detail flow, masked virtual-card presentation, sandbox payment-method entry, card assignment, all five modes on `/rules`, proposed/approved/history review, credential reveal re-authentication, and purchase/subscription history.

## Root infrastructure commands

| Command | Effect |
| --- | --- |
| `make init-env` | Create root `.env` from the example if absent |
| `make infra-check` | Validate the resolved Compose configuration |
| `make infra-up` | Start services and wait for health checks |
| `make infra-ps` | Show service state |
| `make infra-logs` | Follow PostgreSQL, Redis, and pgAdmin logs |
| `make infra-restart` | Restart services |
| `make infra-down` | Stop services while preserving named volumes |

Equivalent direct Compose commands are available, but the Make targets keep the common workflow consistent.

### Deliberately resetting local data

This command deletes the named local PostgreSQL, Redis, and pgAdmin volumes:

```bash
docker compose down --volumes
```

Use it only for intentionally disposable local data. `make infra-down` is the normal non-destructive stop command.

## Connecting between host and Compose

The API currently runs on the host, so its development URLs use `localhost`:

```text
postgresql+asyncpg://agpay:agpay_postgres_dev@localhost:5432/agpay
redis://:agpay_redis_dev@localhost:6379/0
```

Another Compose service would use the Docker service names `postgres:5432` and `redis:6379`. In pgAdmin, register PostgreSQL with host `postgres`, port `5432`, and values from the root `.env`.

## Environment boundaries

There are four local environment files with different ownership:

- root `.env`: Docker Compose database/Redis/pgAdmin credentials and published ports;
- `dev/ag-pay-platform/.env`: API connection URLs, authentication/token settings, encryption key, and CORS origins;
- `dev/ag-pay-platform/apps/web/.env.local`: server-side FastAPI origin for the Next.js BFF;
- `dev/ag-openclaw-playground/.env`: local Gateway token, optional model-provider key, and API bridge settings.

All four are ignored. Their `.env.example` counterparts are safe templates. Ensure passwords in the API URLs match the root Compose values.

Important API variables include:

- `DATABASE_URL`, `REDIS_URL`;
- `JWT_SECRET`, access-token lifetime;
- agent-token, pairing-token, and online-window lifetimes;
- `CREDENTIAL_ENCRYPTION_KEY` as a valid Fernet key;
- `CORS_ORIGINS`.

Generate independent random JWT and credential-encryption keys. The development fallback derives the Fernet key from `JWT_SECRET`; do not use that fallback in a shared or production environment.

## Database migrations

- Every durable schema change gets an Alembic revision committed with its code.
- CI must create a fresh database and upgrade from the empty base to head.
- Destructive schema changes need an explicit data migration and recovery plan.
- Application replicas should not all auto-run migrations at startup.
- Production migrations run as a controlled release step with a current backup.
- When releases exist, test upgrading from the last released revision as well as from empty.

## Development quality gates

Before merging API changes:

- Ruff linting and the test suite pass;
- a fresh PostgreSQL Alembic upgrade succeeds;
- human/agent credential-audience tests pass;
- cross-tenant negative tests cover every owned resource;
- concurrent cart approval/cancel/completion behavior is tested;
- card assignment and disable/revoke edge cases pass;
- policy tenant isolation, default `always`, strict-greater totals, recurrence modes, currency mismatch, and no-active-card fallback pass;
- no live PAN/CVC appears in tests, logs, or durable fixture data; direct-card
  boundary tests use only synthetic values and assert that plaintext is absent
  from responses, events, logs, and PostgreSQL;
- bearer tokens, pairing tokens, and merchant passwords do not appear in
  logs/fixtures;
- dependency/container findings are reviewed.

Before merging web changes:

- ESLint, TypeScript, and the production Next.js build pass;
- protected screens redirect when no valid session is present;
- bearer tokens never appear in browser storage, client bundles, URLs, logs, or rendered content;
- the BFF allowlist exposes only intended human operations and clears expired/invalid cookies;
- normal provider forms contain no PAN/CVC fields; the local research form keeps
  PAN out of React/query state and the managed-approval form collects CVC only
  for a selected direct card; no form accepts PIN or 3-D Secure secrets;
- approval copy distinguishes managed checkout from legacy external completion,
  states that approving an item without both checkout fields queues no payment,
  and never implies broader merchant/provider support than the configured
  adapter;
- rules copy distinguishes automatic control-plane approval from issuer permission and explains same-currency strict-greater thresholds;
- desktop and narrow-viewport management journeys receive a browser smoke test.

## Seed and test data

Use deterministic fake users, fake merchant credentials, and provider sandbox references. Never include real card numbers or credentials in migrations, seeds, tests, examples, screenshots, issue trackers, or prompts. Seed commands should remain separate from migrations so schema deployment never creates demonstration accounts.

After registering the account and applying migrations, seed the current local demonstration set from `dev/ag-pay-platform`:

```bash
make seed-demo SEED_USERNAME=your-existing-username
```

The idempotent seeder creates seven named OpenClaw/Hermes agents and assigns fake Qonto Mastercard metadata ending in `2048` to them. It creates ten completed purchases, including four monthly USD service subscriptions priced at $20 or more, plus three `proposed` items and one `approved` item. The Qonto/provider/order data is presentation-only test metadata; it is not connected to Qonto and contains no raw card credential. The target user must already exist, and rerunning recognizes the seeded provider references rather than duplicating purchases.

## Cross-repository compatibility

The FastAPI OpenAPI document and [HTTP API overview](./api.md) define the current contract. The web BFF uses the human endpoints, while the `ag-plugin-openclaw` repository uses the versioned agent endpoints. A future mobile client and broader SDK should pin an API/SDK version. Keep authorization and financial invariants in the backend; clients present and request decisions but never become their enforcement point.
