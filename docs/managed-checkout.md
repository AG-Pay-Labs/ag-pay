# Managed checkout

## What is implemented

Managed checkout is an opt-in, post-approval execution path. An agent still
researches a product and submits a cart item. When that item includes a
server-configured checkout adapter and an HTTPS checkout URL, approval and job
creation happen in one PostgreSQL transaction.

Three deliberately bounded provider/fixture paths are implemented:

- the configured-merchant rail retrieves a tenant-bound Stripe Issuing virtual
  card and submits it through an operator-reviewed merchant adapter; and
- the development-only `stripe-hosted` proof creates a Stripe **test-mode**
  Checkout Session from the exact approved title, quantity, unit amount, and
  currency, then has Browserbase fill Stripe's hosted page with a selected
  built-in test fixture; or
- the development/test-only Link path can use a US owner's
  `stripe_link`/`csmrpd_...` reference with either a configured direct adapter
  or the built-in hosted proof: it creates a test-mode Link SpendRequest, waits
  for a separate Link approval, and retrieves a one-time test credential
  through an owner-scoped Link CLI session.

The hosted proof is the recommended end-to-end demo because Stripe is publicly
reachable from Browserbase and its API provides an authoritative success or
decline result. The supplied `product_url` remains evidence for the proposal;
the proof does not add an item to that source merchant's cart, create an order
there, or claim arbitrary-site purchasing.

For the configured-merchant rail, a separate worker:

1. locks and leases the queued execution, then takes a PostgreSQL advisory lock
   for the selected Issuing card so two workers cannot correlate concurrent
   same-card authorizations to the wrong order;
2. revalidates the agent, card assignment, cart state, exact amount, currency,
   adapter snapshot, and the single checkout origin frozen by human approval;
3. opens a Browserbase session with recording, session logging, and CAPTCHA
   solving disabled for configured-merchant/Issuing sessions;
4. verifies the merchant's displayed product title, quantity, and total before
   retrieving card data and again immediately before submission;
5. retrieves an active Stripe Issuing virtual card directly in worker memory;
6. retrieves the card, persists the irreversible boundary immediately before
   the first secret field is filled, then fills bound operator-owned
   Playwright elements and performs the final submit;
7. verifies both a merchant success state and one matching, newly observed
   Stripe Issuing authorization; when Stripe supplies merchant-presentment
   fields, their amount and currency—not a converted cardholder amount—must
   match the approval exactly; and
8. atomically creates the purchase, marks the cart item purchased, and appends
   a sanitized checkout event. A bounded merchant order reference is retained
   for the human reconciliation view but is not included in agent events.

The OpenClaw plugin polls the agent-scoped durable event feed. It persists the
purchase-request-to-session mapping locally, injects a fixed safe outcome into
the originating session, and requests an event heartbeat. Browserbase IDs,
provider references, raw errors, merchant HTML, and card data are not sent to
OpenClaw.

For `stripe-hosted`, the worker creates the provider session only after human
approval. It binds both the Checkout Session and resulting PaymentIntent to the
execution ID, checks test mode plus exact amount/currency metadata through the
Stripe API, and treats the provider response—not page copy or a redirect—as the
terminal authority. With a Link method, the worker first creates a separately
approved, test-mode SpendRequest from the same frozen facts; Link approval
releases the test credential but does not establish merchant success. A
verified decline becomes `failed` with `payment_declined`; a verified payment
becomes `succeeded` and creates the AG Pay purchase record; a required challenge
becomes `action_required`; and an unverifiable post-submit result becomes
`outcome_unknown` without retry.

This is deliberately not a universal arbitrary-site buyer. Only explicit
adapter keys and origins configured by the platform operator are eligible.
Unknown adapters, private hosts, changed merchant origins, unlisted frames, ambiguous
forms, total drift, unsupported providers, CAPTCHA, and 3-D Secure or other
interactive challenges fail closed. Managed proposals also reject currency
codes outside the worker's explicit Stripe presentment set and amounts that
cannot be represented in that currency's minor-unit exponent.

An adapter may list resource and payment-frame origins, but the top-level
merchant, line-item checks, submit control, success marker, and receipt remain
bound to the one origin captured from the approved checkout URL. Another origin
in the adapter cannot replace that merchant during execution.

For this test-mode increment, an enabled adapter must target a catalog where
the normalized displayed title uniquely identifies the approved item/variant.
The worker also checks quantity and exact total twice, but it does not yet bind
an immutable merchant SKU or variant ID from `product_url` to the checkout line
item. Do not enable real-money merchants with ambiguous same-title variants.

The implemented managed path is one-time purchase only. A proposal with
`billing_period=monthly|yearly` is rejected from managed queueing because the
worker cannot yet prove the merchant's renewal amount and interval. Recurring
proposals can still use the legacy sandbox/external completion path.

Managed checkout always starts as `proposed` and requires the owner to use the
human approval endpoint, even if the agent's legacy review policy is `never` or
would otherwise auto-approve the amount. A payment policy cannot create an
executable checkout grant.

## State and retry contract

`CheckoutExecution` is the PostgreSQL source of truth:

```text
queued -> running -> succeeded
                  -> failed
                  -> action_required
                  -> outcome_unknown
```

The worker may retry a safe, retryable error only before `submitted_at` is
persisted. Card-field scripts may tokenize or submit on input/change, so this
boundary is recorded before the first PAN/CVC fill—not merely before the final
button click. After that, a crash, timeout, disconnected browser, fill error, or
unverifiable provider result becomes `outcome_unknown`. It is never
automatically submitted again. This is the central double-charge safeguard.

An `action_required` or `outcome_unknown` execution also quarantines its
selected payment method from later managed jobs. A job that was already queued
with that method stops before card disclosure. This prototype has no automatic
unquarantine action: reconcile the merchant and issuer, disable the method, and
use a distinct virtual card for a new approved request.

`CheckoutEvent` is the durable, agent-scoped terminal outcome feed. Redis
publication is only a best-effort wake/observability aid and is not required for
recovery.

`CheckoutStatusTransition` is the separate durable human lifecycle history.
It records initial queueing, every worker claim, safe pre-submit requeue, and
the terminal outcome in the same transactions as the corresponding execution
state changes. This history is shown in AG Pay but is not sent to OpenClaw.

## Credential boundary

- The database stores `provider=stripe_issuing` and an opaque `ic_...` card ID,
  plus non-sensitive display metadata. It has no PAN or CVC column.
- Payment-method creation fails closed to the implemented opaque-reference
  formats: `stripe_issuing`/`ic_...`, development-only
  `stripe_link`/`csmrpd_...`, and the legacy test-only
  `prototype-vault`/`pm_...`. Unknown providers and values resembling PAN or
  CVC data are rejected before persistence.
- The worker accepts the card only when provider-owned Stripe metadata binds
  `agpay_owner_id` to the execution's tenant. A tenant-supplied card reference
  cannot establish or override that binding.
- `STRIPE_SECRET_KEY` and Browserbase credentials belong only to the checkout
  worker environment. The web-facing API settings do not consume them. Do not
  put them in the OpenClaw playground, plugin configuration, Compose file,
  repository, or chat.
- The worker expands the virtual card number and CVC only immediately before
  deterministic form filling. No model or Stagehand call receives them.
- On the hosted development rail, the database stores only one of the safe
  `pm_stripe_demo_*` references or an opaque `csmrpd_...` Link reference. The
  corresponding public Stripe or Link test value is materialized only inside
  the trusted worker for form fill; it is not an API, web, OpenClaw, database,
  or telemetry field.
- Link CLI authentication is selected from a worker-only directory by the
  execution's immutable owner ID. One owner's auth file is never a fallback for
  another owner. The pinned CLI writes the one-time credential to a private
  file for direct worker consumption instead of stdout; the worker removes the
  file after reading it and never logs its contents.
- Configured-merchant and Issuing payment sessions use `recordSession=false`,
  `logSession=false`, `solveCaptchas=false`, no persistent Browserbase context,
  and an origin allowlist. The built-in development-only `stripe-hosted` rail
  hardcodes `recordSession=true` and `logSession=true` so operators can replay
  checkouts that use only public Stripe test-card fixtures. Browserbase's domain
  control is defense in depth; the worker also validates every top-level page
  and frame before filling or submitting.
- The Browserbase account, worker process, provider account, and operational
  access are still in the card-data trust boundary. PCI, legal, provider, and
  incident-response review remain production launch requirements.

## Local configuration

Managed checkout is off by default. For local development only, the API and
worker commands can read the same untracked `dev/ag-pay-platform/.env`; this is
a convenience and gives both OS processes access to the same file. The API
settings object ignores provider-secret fields, but an API compromise with
filesystem access could still read that shared file. In every deployed
environment, inject provider credentials only into the worker process from a
secret manager and do not mount its secret source into the API container. The
checked-in `.env.example` contains names and safe placeholders only.

```dotenv
CHECKOUT_ENABLED=true
BROWSERBASE_API_KEY=bb_live_or_test_value
BROWSERBASE_PROJECT_ID=your_project_id
BROWSERBASE_REGION=eu-central-1
STRIPE_SECRET_KEY=sk_test_value
CHECKOUT_WORKER_POLL_SECONDS=1
CHECKOUT_LEASE_SECONDS=120
CHECKOUT_MAX_ATTEMPTS=3
CHECKOUT_RESULT_TIMEOUT_SECONDS=60
CHECKOUT_AUTHORIZATION_TIMEOUT_SECONDS=30
CHECKOUT_AUTHORIZATION_POLL_SECONDS=1
CHECKOUT_ADAPTERS={"sandbox_store":{"allowed_origins":["https://checkout.example.test"],"payment_origins":["https://checkout.example.test"],"product_title_selector":"[data-test=product-title]","quantity_selector":"[data-test=quantity]","total_selector":"[data-test=total]","card_number_selector":"[data-test=card-number]","expiry_selector":"[data-test=expiry]","cvc_selector":"[data-test=cvc]","submit_selector":"[data-test=submit]","success_selector":"[data-test=success]","action_required_selector":"[data-test=action-required]","order_reference_selector":"[data-test=order-id]","receipt_url_selector":"[data-test=receipt]"}}
```

The example origin is illustrative and must be replaced with a public HTTPS
sandbox merchant controlled or explicitly trusted by the operator. Browserbase
cannot reach a normal `localhost` fixture. Selectors are CSS selectors owned by
the platform configuration; never accept model-generated selectors at runtime.
The element matched by `total_selector` must display the approved three-letter
ISO currency code next to the total; ambiguous symbols such as `$` or `¥` alone
are rejected.
For hosted payment fields, list the payment iframe's exact HTTPS origin in
`payment_origins` while keeping the merchant origin in `allowed_origins`.
If the checkout needs a separate CDN or API, add each reviewed exact HTTPS
origin to `resource_origins`; wildcards are not supported. JavaScript origins
enter the card-data trust boundary, so include only resources required by the
specific adapter. Service workers and all WebSocket connections remain blocked.

Run migrations before starting the worker:

```bash
cd dev/ag-pay-platform
make api-install
make api-migrate
make checkout-worker
```

Worker startup fails closed when checkout is disabled or the Browserbase and
Stripe credentials required by the enabled rail are missing. Invalid or absent
adapter configuration prevents a new managed request from being approved; an
already frozen valid execution can still be recovered by the worker.

The optional Stripe Link proof has additional worker-only settings and setup.
It fails startup outside `development`/`test` or without Link test mode, and
uses a separately authenticated owner file for each platform owner. Follow
[Stripe Link agent payments](./stripe-link-agent-payments.md) for the pinned CLI
version, exact environment, authentication, and end-to-end procedure.

## Automated verification

The automated suite uses fake browser and issuer boundaries; it never opens a
Browserbase session and never creates a charge:

```bash
cd dev/ag-pay-platform
make lint
make test
make web-build

cd ../ag-plugin-openclaw
make check
make pack-check

cd ../ag-openclaw-playground
make check
make smoke
```

These checks cover transactional queueing, tenant and assignment revalidation,
single-worker claiming, per-card serialization, pre-submit retry, post-submit
ambiguity, exact product, quantity, total, and origin checks, disabled
Browserbase recording/logging, new-authorization correlation, safe event
serialization, OpenClaw session routing, restart recovery, and event
deduplication. Playground smoke is non-purchasing and proves only the Gateway,
plugin, SecretRef, and tool/service surfaces.

## Stripe-hosted Browserbase proof (recommended)

This is the shortest truthful end-to-end demonstration of the concept. The
agent can inspect any public product page and submit its URL plus exact product
facts. After the human approves, AG Pay creates a new Stripe test-mode Checkout
Session containing those approved facts, Browserbase fills the hosted Stripe
form from AG Pay's saved billing profile and selected fake card fixture, and
the worker waits for Stripe's API result. No local merchant, HTTPS tunnel,
publishable key, port `8100`, real card, or Stripe Issuing card is involved.

This proves the supervised workflow, browser form filling, provider outcome
detection, durable status history, web notification, and OpenClaw callback. It
does **not** prove a purchase from the product URL's merchant. A `succeeded`
result is a Stripe test-mode payment and an AG Pay purchase record only.

The standard procedure below uses fixed public Stripe card fixtures. The
alternative `stripe_link` hosted proof adds an eligible US Link account and a
second Link approval, but retains the same Stripe test Checkout
Session/PaymentIntent as merchant authority. Follow
[Stripe Link agent payments](./stripe-link-agent-payments.md) for that variant;
never substitute a live Link credential into this recorded test rail.

### 1. Create test accounts

1. In Stripe, enable **Test mode** and copy an `sk_test_...` secret key from
   **Developers → API keys**. A `pk_test_...` key is not needed for this rail.
2. In Browserbase, create a project and copy its project ID and API key.
3. Keep both values in the untracked platform `.env`; never put them in
   OpenClaw configuration, a prompt, source control, or chat.

### 2. Configure `dev/ag-pay-platform/.env`

Start from `.env.example`, retain the existing database/application values, and
set the checkout values below:

```dotenv
ENVIRONMENT=development
CHECKOUT_ENABLED=true
CHECKOUT_DEMO_ENABLED=true
CHECKOUT_HOSTED_DEMO_ENABLED=true
BROWSERBASE_API_KEY=your_browserbase_key
BROWSERBASE_PROJECT_ID=your_browserbase_project_id
BROWSERBASE_REGION=eu-central-1
STRIPE_DEMO_SECRET_KEY=sk_test_your_stripe_test_secret
```

`CHECKOUT_HOSTED_DEMO_ENABLED=true` installs the pinned `stripe-hosted` adapter
with bootstrap URL `https://checkout.stripe.com/`. It requires
`CHECKOUT_DEMO_ENABLED=true`, accepts only the built-in demo payment-method
references, and fails startup outside `development` or `test`. Do not add or
override `stripe-hosted` in `CHECKOUT_ADAPTERS`. `STRIPE_SECRET_KEY` is for the
separate Issuing rail and is not required here.

### 3. Start the platform

Use a separate terminal for each long-running process:

```bash
cd ag-pay
make infra-up
```

```bash
cd ag-pay/dev/ag-pay-platform
make api-install
make api-migrate
make api-run
```

```bash
cd ag-pay/dev/ag-pay-platform
make web-install
make web-run
```

```bash
cd ag-pay/dev/ag-pay-platform
make checkout-worker
```

Open AG Pay at `http://127.0.0.1:3000`. The API runs on port `8000`; nothing for
this hosted proof runs on port `8100`.

### 4. Create the supervised test identity

1. Register or sign in to AG Pay.
2. Start the playground and its packaged sibling plugin:

```bash
cd ag-pay/dev/ag-openclaw-playground
make init
# Add a model-provider key to the untracked .env only if a model-backed turn is needed.
make check
make smoke
make ps
make dashboard
```

3. Create an agent in AG Pay, then run `make pair` in the playground and enter
   the one-time token only at its hidden prompt. Run `make smoke` again to check
   the paired plugin surfaces. Smoke does not execute or prove a purchase.
4. Seed the three safe test payment methods and assign them to the account's
   agents:

```bash
cd ag-pay/dev/ag-pay-platform
make seed-checkout-demo SEED_USERNAME=your-login-email@example.com
```

Refresh **Cards**. The account now has **Stripe demo · succeeds**, **Stripe demo
· declines**, and **Stripe demo · 3DS**, each with a complete fake billing
profile. The database contains safe references and display metadata, not raw
card fields.

The standard playground configuration supplies the plugin default pair
`stripe-hosted` and `https://checkout.stripe.com/`. When running OpenClaw another
way, configure the same non-secret pair as `defaultCheckoutAdapter` and
`defaultCheckoutUrl`, or supply both checkout fields explicitly. The platform,
not OpenClaw, owns Browserbase and Stripe credentials.

### 5. Ask OpenClaw for a one-time purchase

Give OpenClaw a public product link and make the expected facts explicit for a
repeatable demo. Replace the placeholders below with facts visible on that
page. The normalized title must be at most 127 characters so Stripe Checkout
can display and AG Pay can verify it without truncation:

```text
Inspect <PUBLIC_PRODUCT_URL> and request human approval through AG Pay for
<QUANTITY> units of “<EXACT_PRODUCT_TITLE>” at exactly <CURRENCY>
<UNIT_PRICE> each. Use that page as the product URL. This is a one-time
purchase. Do not claim it was purchased from the source merchant; wait for AG
Pay's terminal checkout outcome.
```

The OpenClaw tool sends the product URL, normalized title, description,
merchant, reason, quantity, unit price, currency, and merchant-account fields.
For a one-time request that omits checkout fields, the plugin adds its configured
default pair after the model call. AG Pay stores the request as `proposed`; no
Stripe Checkout Session exists yet.

### 6. Approve and watch the provider outcome

1. Open **Approvals** and verify the source URL, title, quantity, unit price,
   currency, and total.
2. Select **Stripe demo · declines** and approve. Approval and the initial
   `queued` execution history entry commit together.
3. The worker claims the job (`running`), creates a `cs_test_...` Checkout
   Session from the frozen facts, opens Browserbase, verifies Stripe's displayed
   item/quantity/total, fills the saved billing fields and fake card, and
   submits once.
4. While it is active, use **Open Browserbase session** on the approval card to
   inspect the browser. Do not grant that live-view access outside trusted test
   operators.
5. The worker polls Stripe for the exact Checkout Session and expanded
   PaymentIntent, checking test mode, execution metadata, amount, and currency.
   For the official decline fixture, it expires the exact session and requires
   Stripe to return that session as test-mode, unpaid, expired, and bound to the
   execution before recording `failed/payment_declined`. If expiration cannot
   be established, it records `outcome_unknown` instead. Neither path creates a
   purchase row.
6. The web app polls active executions, renders the ordered
   `queued → running → failed` timeline, routes the item to **Needs attention**,
   and shows a one-time failure toast. The terminal event is persisted for the
   agent; the OpenClaw outcome monitor delivers a fixed sanitized failure to the
   originating session and requests its next turn.

Repeat with **Stripe demo · succeeds**. The expected timeline is
`queued → running → succeeded`; AG Pay creates one purchase record and can
retain Stripe's safe test receipt URL. **Stripe demo · 3DS** exercises
`action_required`. If submission may have happened but Stripe cannot establish
the result within the bounded polling window, expect `outcome_unknown` and
reconcile manually—never approve a blind retry.

### 7. What to verify

- The request cannot queue until a human selects an assigned method and
  approves it.
- The Checkout Session line item exactly matches the approved title, quantity,
  amount, and currency; changing displayed facts fails closed before fill.
- The decline path ends in `failed/payment_declined`, appears in the panel, and
  creates no purchase.
- The success path ends in `succeeded`, appears in history, and creates exactly
  one AG Pay purchase backed by a verified test PaymentIntent.
- OpenClaw receives only the request ID, safe status, amount/currency, purchase
  ID when present, and fixed error code—not a browser session, provider secret,
  raw provider error, or card field.

## Local demo-merchant rail (optional legacy fixture)

This development-only rail uses Stripe Payments test mode, a fixed AG Pay demo
merchant, Browserbase, and Stripe's
official decline fixture. It does **not** require a Stripe Issuing card,
`agpay_owner_id` metadata, a real card, or a charge. AG Pay and OpenClaw see only
`pm_stripe_demo_decline`; test card values exist only inside the trusted worker.

Prefer the hosted proof above. This older fixture remains useful when changing
the direct adapter implementation itself, but it requires the local merchant on
port `8100`, a public HTTPS tunnel, and a Stripe test publishable key.

### 1. Create the sandbox accounts

1. In Stripe, enable **Test mode**, then copy the `pk_test_...` publishable key
   and `sk_test_...` secret key from **Developers → API keys**.
2. In Browserbase, create a project and copy its project ID and API key.
3. Never paste those keys into chat or OpenClaw.

### 2. Configure `dev/ag-pay-platform/.env`

Replace `https://YOUR-DEMO-HOST` with the public HTTPS origin from step 4:

```dotenv
CHECKOUT_ENABLED=true
CHECKOUT_DEMO_ENABLED=true
CHECKOUT_DEMO_ADAPTER_KEY=stripe-demo
BROWSERBASE_API_KEY=your_browserbase_key
BROWSERBASE_PROJECT_ID=your_browserbase_project_id
STRIPE_DEMO_SECRET_KEY=sk_test_your_stripe_test_secret
STRIPE_DEMO_PUBLISHABLE_KEY=pk_test_your_stripe_publishable_key
DEMO_PRODUCT_TITLE=AG Pay Browserbase Demo
DEMO_AMOUNT_MINOR=2500
DEMO_CURRENCY=EUR
CHECKOUT_DEMO_OBSERVATION_SECONDS=30
CHECKOUT_ADAPTERS={"stripe-demo":{"allowed_origins":["https://YOUR-DEMO-HOST"],"payment_origins":["https://js.stripe.com","https://m.stripe.network"],"resource_origins":["https://api.stripe.com","https://js.stripe.com","https://m.stripe.com","https://q.stripe.com","https://r.stripe.com","https://hooks.stripe.com","https://b.stripecdn.com"],"product_title_selector":"[data-checkout-product-title]","quantity_selector":"[data-checkout-quantity]","total_selector":"[data-checkout-total]","card_number_selector":"input[name='cardnumber']","expiry_selector":"input[name='exp-date']","cvc_selector":"input[name='cvc']","submit_selector":"#submit","success_selector":"[data-order-confirmed]","decline_selector":"[data-payment-failed]","action_required_selector":"[data-action-required]","order_reference_selector":"[data-order-reference]"}}
```

Stripe Elements currently creates frames on both `js.stripe.com` and
`m.stripe.network`, so both exact origins must be reviewed and listed in
`payment_origins`. More generally, list every permitted checkout iframe origin
there; `resource_origins` is only for non-frame network resources.

### 3. Start each service in its own terminal

```bash
cd ag-pay
make infra-up
```

```bash
cd ag-pay/dev/ag-pay-platform
make api-migrate && make api-run
```

```bash
cd ag-pay/dev/ag-pay-platform
make web-run
```

```bash
cd ag-pay/dev/ag-pay-platform
make demo-merchant-run
```

```bash
cd ag-pay/dev/ag-pay-platform
make checkout-worker
```

### 4. Give Browserbase a public merchant URL

Browserbase cannot reach localhost. Expose only port `8100` with a trusted HTTPS
tunnel or deploy the demo merchant. If `cloudflared` is already installed:

```bash
cloudflared tunnel --url http://127.0.0.1:8100
```

Put the emitted `https://...trycloudflare.com` origin in `CHECKOUT_ADAPTERS`,
then restart the API and worker. Do not tunnel the AG Pay API, database, Redis,
or OpenClaw. Verify `https://YOUR-DEMO-HOST/health/live` and
`https://YOUR-DEMO-HOST/product` in a normal browser.

### 5. Seed safe demo payment methods

Create your AG Pay user and at least one agent in the UI, pair OpenClaw, then run:

```bash
cd ag-pay/dev/ag-pay-platform
make seed-checkout-demo SEED_USERNAME=your-login-email@example.com
```

Refresh **Cards**. You will see `Stripe demo · succeeds`,
`Stripe demo · declines`, and `Stripe demo · 3DS`, assigned to existing agents.
No raw card number is stored.

### 6. Ask OpenClaw to buy it

Send this prompt with your public host:

```text
Open https://YOUR-DEMO-HOST/product and inspect the product. Submit a one-time
AG Pay managed purchase request for exactly 1 “AG Pay Browserbase Demo” at
EUR 25.00. Use checkout adapter stripe-demo and checkout URL
https://YOUR-DEMO-HOST/checkout. Do not report completion yourself; wait for
AG Pay's checkout outcome.
```

### 7. Approve and observe the decline

1. In AG Pay **Approvals**, verify the product facts.
2. Select **Stripe demo · declines** and approve.
3. Watch `queued → running → failed`. While running, click
   **Open Browserbase session** to see Stripe Elements filled and submitted.
4. AG Pay retrieves the exact PaymentIntent and verifies test mode, EUR 25.00,
   execution ID, and declined status before recording `payment_declined`.
5. The user sees the failed execution and no purchase row. The OpenClaw outcome
   monitor injects the safe failure into the originating session and wakes it.

Repeat with **Stripe demo · succeeds** for the success branch. The 3DS method
exercises the `action_required` branch.

## Stripe Issuing managed-checkout procedure

Stripe Issuing sandbox cards cannot perform an actual external card-form
purchase, so use the Payments demo above for sandbox pass/decline testing. The
procedure below is for a controlled provider environment after confirming the
applicable Stripe mode and merchant support. Never point it at an arbitrary
production shop.

1. In Browserbase, create a development project and place its API key and
   project ID in the platform `.env`.
2. In Stripe test mode, create or select an active **virtual Issuing card**.
   Read the test owner's UUID from authenticated `GET /api/v1/auth/me`, then,
   from a trusted operator context, set the card's Stripe metadata to
   `agpay_owner_id=<that UUID>`. Put the Stripe secret key in the platform
   `.env`; enter only the card's opaque `ic_...` ID and exact safe display
   metadata in AG Pay. The worker rejects absent or mismatched owner metadata;
   this binding must never come from the payment-method form or agent input.
3. Deploy or expose the sandbox merchant at public HTTPS. It must display one
   exact total, accept the test Issuing card, expose deterministic form/success
   selectors, and create a Stripe Issuing authorization.
4. Add an adapter entry for that merchant. Keep merchant and hosted-payment
   origins exact; do not use wildcards.
5. Start PostgreSQL/Redis, migrate, and run the API, web app, and checkout worker
   in separate terminals.
6. In AG Pay, create the `stripe_issuing` payment method using the `ic_...`
   reference, assign it to the test agent, and leave the agent policy on
   `always` for the first test.
7. Pair the playground through `make pair`. Never pass the pairing token on a
   command line.
8. Have OpenClaw research the sandbox product and call
   `agpay_request_purchase` with the verified product facts plus
   `checkout_adapter=sandbox_store` and the exact public checkout URL.
   Keep `billing_period` null for managed checkout.
9. In the AG Pay Approvals screen, inspect the item, amount, currency, merchant,
   and adapter, then approve it with the Issuing method.
10. Observe `queued` then `running`. A valid test purchase becomes `succeeded`,
    the cart item becomes `purchased`, and one purchase record appears. Confirm
    its merchant order reference matches the sandbox merchant's receipt.
11. Verify that the originating OpenClaw session receives the sanitized success
    event without calling the legacy result-recording tool.
12. Repeat with a wrong displayed total, unlisted redirect/frame origin, disabled
    card, and simulated challenge. Expect `failed` or `action_required`, no
    purchase row, and no automatic resubmission after the submit boundary.
13. Set the test agent's review policy to `never` and submit another managed
    request. It must still remain `proposed` with no selected card or execution
    until the human approves it.

If an execution becomes `outcome_unknown`, stop. Reconcile the Stripe
authorization and merchant order manually before any new attempt. The prototype
intentionally has no "retry unknown" button.

## Production gates

Before non-test money, add provider-hosted card onboarding and metadata
verification, one-execution virtual-card controls, signed provider webhooks,
an immutable merchant SKU/variant binding, merchant/order reconciliation,
approval expiry or an all-in total cap, durable
audit logging, secret-manager deployment, restricted Browserbase live-view
access or a contractual zero-data-retention control, alerts/runbooks, and a PCI
and legal assessment. Each new merchant needs a reviewed adapter and threat
model.

## Provider references

- [Browserbase session settings](https://docs.browserbase.com/reference/sdk/python)
  and [session recording controls](https://docs.browserbase.com/platform/browser/observability/session-recording)
- [Browserbase allowed-domain limitations](https://docs.browserbase.com/platform/browser/security/allowed-domains)
- [Stripe Issuing virtual cards](https://docs.stripe.com/issuing/cards/virtual)
- [Stripe Issuing authorization API](https://docs.stripe.com/api/issuing/authorizations/list?lang=python)
- [Stripe Link CLI](https://github.com/stripe/link-cli)
- [Stripe Link for agents](https://link.com/agents)
