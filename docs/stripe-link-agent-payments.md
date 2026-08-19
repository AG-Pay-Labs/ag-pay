# Stripe Link agent payments: local setup and test

This guide exercises AG Pay's development-only `stripe_link` provider through
the built-in `stripe-hosted` checkout proof. A human first approves the cart
item in AG Pay, then approves a Stripe Link SpendRequest in the Link app. The
trusted checkout worker obtains a test, one-time virtual card from Link and
uses it in a Stripe test-mode Checkout Session through Browserbase.

The test does not charge the card saved in Link. It proves the AG Pay approval,
tenant-scoped Link session, one-time credential handoff, browser submission,
the allowlisted landing server's paid-session verification, durable status
timeline, and purchase record. The worker opens an existing offer-specific
Checkout Session URL; it neither creates nor polls a Stripe session and holds
no Stripe credential. It does not prove arbitrary-merchant compatibility or
production readiness.

The integration is pinned to `@stripe/link-cli` `0.12.0`. The worker parses the
CLI's JSON contract, so upgrading the CLI requires rerunning the automated and
end-to-end tests before deployment.

Official references:

- [Link CLI repository and command reference](https://github.com/stripe/link-cli)
- [Stripe's agent wallet overview](https://link.com/agents)
- [Stripe's Link agent skill and safety contract](https://link.com/skill.md)
- [Stripe test-mode documentation](https://docs.stripe.com/testing)

## Boundaries and prerequisites

You need:

- a **US Link account** with at least one eligible saved card and access to the
  Link app; Stripe currently limits Link's agent wallet to US Link accounts;
- Node.js `24.15.x` and npm, plus the repository's Python `3.12`, pnpm `11.9.0`,
  Docker with Compose v2, and Make;
- a Browserbase API key and project ID;
- one full test-mode Checkout Session URL for the exact published playground
  offer being tested; and
- free local ports `3000`, `5050`, `5432`, `6379`, and `8000`.

The Checkout URL must start with
`https://checkout.stripe.com/c/pay/cs_test_` and retain its `#...` fragment. A
generic Stripe root is not executable, and one fixed URL cannot represent more
than one offer. The `letyouragentspay.com` landing deployment owns the Stripe
test secret used for server-side receipt verification; do not give it to the
worker.

Link's `csmrpd_...` value is an opaque saved-payment-method reference. It is
safe to store as a provider reference, but it is still tenant data and should
not appear in public logs. Never enter a card number, CVC, Link access token,
refresh token, AG Pay bearer token, or platform password in source files, chat,
screenshots, or command arguments.

## 1. Install and inspect the pinned Link CLI

Install the exact version expected by AG Pay:

```bash
npm install -g @stripe/link-cli@0.12.0
link-cli --version
link-cli spend-request create --schema
```

The reported version must be `0.12.0`. Do not replace the pin with `latest`
without first updating and regression-testing the gateway.

## 2. Create a private owner-auth directory

AG Pay deliberately does not use Link's default global session. Each platform
owner gets a separate auth file inside a worker-only directory. Create a
private directory outside the repository; the final directory and file paths
must be absolute:

```bash
umask 077
AGPAY_LINK_PRIVATE_DIR="$(mktemp -d)"
chmod 700 "$AGPAY_LINK_PRIVATE_DIR"
printf '%s\n' "$AGPAY_LINK_PRIVATE_DIR"
```

Keep that printed directory path locally; it is not a credential, but it tells
the worker where the credential files live. Do not place the directory under
`ag-pay`, copy it to cloud storage, or commit it. Keep this shell open, because
Step 6 uses `AGPAY_LINK_PRIVATE_DIR`. If you open a new shell, set that variable
to the same absolute directory first.

## 3. Create local environment files

From the base repository:

```bash
cd /Users/vitaliibulyzhyn/Desktop/ag-pay
make init-env
cd dev/ag-pay-platform
test -f .env || cp .env.example .env
test -f apps/web/.env.local || cp apps/web/.env.example apps/web/.env.local
```

Edit the untracked `dev/ag-pay-platform/.env`; do not print it. Preserve the
existing database, Redis, JWT, and encryption settings. Enable only the local
test rails and add the worker-owned values:

```dotenv
ENVIRONMENT=development
CHECKOUT_ENABLED=true
CHECKOUT_DEMO_ENABLED=true
CHECKOUT_HOSTED_DEMO_ENABLED=true
BROWSERBASE_API_KEY=your_browserbase_key
BROWSERBASE_PROJECT_ID=your_browserbase_project_id
STRIPE_LINK_ENABLED=true
STRIPE_LINK_TEST_MODE=true
STRIPE_LINK_CLI_PATH=link-cli
STRIPE_LINK_CLI_VERSION=0.12.0
STRIPE_LINK_AUTH_DIRECTORY=/absolute/path/printed/in/step-2
STRIPE_LINK_APPROVAL_TIMEOUT_SECONDS=600
STRIPE_LINK_CLI_TIMEOUT_SECONDS=30
```

Do not configure a Stripe secret on this worker for the fixed-URL hosted proof.
The Link auth directory and all Link auth files must be readable only by the
checkout-worker operating-system user.
The FastAPI, Next.js, OpenClaw, and model processes must not receive them in a
deployed environment.

`STRIPE_LINK_AUTH_DIRECTORY` must be the absolute path printed in Step 2, not a
relative path or the path to one auth file. The worker deterministically selects
`<owner UUID>.json` inside this directory. `STRIPE_LINK_TEST_MODE=true` makes
Link return a public test credential and prevents a charge to the saved method.
The approval timeout matches Link's ten-minute approval window; the shorter CLI
timeout applies to individual non-polling commands.

## 4. Start infrastructure and install the applications

Run one command at a time from the base repository:

```bash
cd /Users/vitaliibulyzhyn/Desktop/ag-pay
make infra-check
make infra-up
make infra-ps
```

PostgreSQL, Redis, and pgAdmin must all become healthy. Then install and migrate
the platform:

```bash
cd /Users/vitaliibulyzhyn/Desktop/ag-pay/dev/ag-pay-platform
make api-install
make api-migrate
make web-install
```

For a clean implementation check, run:

```bash
make lint
make test
make web-build
```

## 5. Start the API and web app

Keep two terminals open in
`/Users/vitaliibulyzhyn/Desktop/ag-pay/dev/ag-pay-platform`.

Terminal 1:

```bash
make api-run
```

Terminal 2:

```bash
make web-run
```

Verify the platform without exposing configuration:

```bash
curl --fail --silent --show-error http://127.0.0.1:8000/health/live
curl --fail --silent --show-error http://127.0.0.1:8000/health/ready
```

Both calls should succeed. Open `http://127.0.0.1:3000/login`. Do not start the
worker until the owner-scoped Link session exists.

## 6. Create the owner and authenticate its Link session

Register or log in to AG Pay. While still signed in, open
`http://127.0.0.1:3000/api/auth/session` in the same browser and copy only
`user.id`, which is the platform owner's UUID. Return to the private-directory
shell and enter that UUID at the hidden prompt below:

```bash
printf 'AG Pay owner UUID: '
IFS= read -r AGPAY_OWNER_ID
AGPAY_LINK_OWNER_AUTH_FILE="$AGPAY_LINK_PRIVATE_DIR/$AGPAY_OWNER_ID.json"
```

The filename must be exactly `<owner UUID>.json`; changing case, using the
username, or authenticating Link's default global file will not work. Before
starting a login, check the selected file:

```bash
link-cli auth status --auth "$AGPAY_LINK_OWNER_AUTH_FILE" --format json
```

If it is not authenticated, start the device authorization flow:

```bash
umask 077
link-cli auth login \
  --auth "$AGPAY_LINK_OWNER_AUTH_FILE" \
  --client-name "AG Pay checkout worker" \
  --interval 5 \
  --timeout 300
```

The CLI displays a verification URL and short phrase. Open the URL yourself,
sign in to Link, verify that the client is **AG Pay checkout worker**, and
approve it. Do not send the URL, phrase, or resulting auth file to an agent or
another person.

Keep the resulting file regular, owned by the operating-system user that runs
the worker, and inaccessible to group/other users:

```bash
test -f "$AGPAY_LINK_OWNER_AUTH_FILE" && test ! -L "$AGPAY_LINK_OWNER_AUTH_FILE"
chmod 600 "$AGPAY_LINK_OWNER_AUTH_FILE"
```

The worker rejects a symlink, a file owned by another user, or permissions that
grant any group/other access.

Confirm authentication, then list the wallet's payment methods:

```bash
link-cli auth status --auth "$AGPAY_LINK_OWNER_AUTH_FILE" --format json
link-cli payment-methods list \
  --auth "$AGPAY_LINK_OWNER_AUTH_FILE" \
  --format json
```

Choose an eligible card and record its `id`, which begins `csmrpd_`. Also note
the safe display fields returned by Link: brand, last four digits, and expiry.
Do not retrieve or copy a PAN or CVC.

As an independent CLI smoke test, run:

```bash
link-cli demo --only-card --auth "$AGPAY_LINK_OWNER_AUTH_FILE"
```

The demo always uses Link test mode. Approve its notification in the Link app
and confirm that it completes before debugging AG Pay.

## 7. Create the agent and Link payment method, then start the worker

1. Create an agent from the Agents page. Keep its one-time pairing value local;
   do not paste it into chat or a command argument.
2. Open **Cards**, select **Stripe Link**, and enter only:
   - the `csmrpd_...` ID from `link-cli payment-methods list`;
   - the corresponding brand, last four digits, and expiry; and
   - the cardholder name and billing address exactly as saved for that card in
     Link, including region, postal code, country, and an empty versus populated
     second address line.
3. Never enter the saved card's PAN or CVC. The Stripe Link attachment flow has
   no fields for them; it is separate from the feature-gated local direct-card
   research rail.
4. Open the agent's detail page and assign the new Stripe Link method to that
   agent.

The UI sends `provider=stripe_link` and the opaque `csmrpd_...` reference. The
API rejects unknown provider formats and values resembling raw payment data.
Immediately before use, the worker also requires Link's brand, last four,
expiry, and one-time credential billing address to match the stored safe
metadata. A mismatch fails before browser submission.

Start a third terminal in the platform repository:

```bash
make checkout-worker
```

The worker must see `link-cli` `0.12.0`, the Link settings, and Browserbase
credentials. It does not need `STRIPE_DEMO_SECRET_KEY`; startup fails closed
when required Link settings or the auth directory are invalid. Do not run
`make demo-merchant-run`; the built-in hosted proof uses the selected fixed
Stripe test checkout. Run only one checkout worker during this local ten-minute
approval test.

## 8. Submit a managed checkout proposal

### Recommended: paired OpenClaw plugin

Start the packaged OpenClaw playground and check its non-purchasing surfaces:

```bash
cd /Users/vitaliibulyzhyn/Desktop/ag-pay/dev/ag-openclaw-playground
make init
make check
make smoke
make ps
make dashboard
```

If a model-backed turn is needed, add its provider key only to the playground's
untracked `.env`; never paste that key into chat. Pair the agent only through
the playground's hidden prompt:

```bash
make pair
```

Enter the one-time `pair_...` value when the hidden prompt asks for it. Never
place it in a command argument, environment value, chat, screenshot, or shell
history. The plugin exchanges it directly and stores the resulting `agt_...`
credential in a private SecretRef; neither credential is sent to the model.
Run `make smoke` again to verify pairing. Smoke does not initiate or prove a
purchase.

Do not configure a default checkout pair in the plugin or playground. The
paired agent's `agpay_request_purchase` tool call must explicitly include:

```text
checkout_adapter: stripe-hosted
checkout_url: <FULL_STRIPE_TEST_CHECKOUT_SESSION_URL_FOR_ONE_OFFER>
```

Preserve the URL's fragment. Each call must use the URL for that call's exact
offer; when testing another playground plan, create a new proposal with that
plan's URL. Ask the paired agent to request a one-time test purchase using the
title, amount, and currency encoded by the selected offer:

```text
title: <EXACT_PLAYGROUND_OFFER_TITLE>
description: Development-only Stripe Link integration test
merchant: AG Pay Stripe hosted sandbox
quantity: 1
unit price: <EXACT_OFFER_PRICE>
currency: <EXACT_OFFER_CURRENCY>
product URL: an HTTPS evidence URL for the test item
account email: a test-only merchant-account email
billing period: omitted
```

The OpenClaw plugin generates a distinct random merchant password itself. Do
not supply a real merchant password to the model.

Underneath this safe surface, the plugin calls
`POST /api/v1/agent/cart-items` with the exact product facts, a generated
test-only merchant credential, and the explicit `stripe-hosted` pair from the
same tool call. The plugin does not add checkout fields from configuration. The
API derives owner and agent identity from the paired credential, encrypts the
merchant password, and returns status `proposed`. Do not reproduce this call
with a pairing or agent token in Swagger or a shell command; pairing is allowed
only through the hidden `make pair` flow.

The current OpenClaw tool rejects a missing or partial checkout pair before
contacting AG Pay. Older or direct API-created legacy proposals remain
approval-only: approving one does not create a worker job, Link SpendRequest,
or payment attempt. Existing legacy proposals and approvals cannot accept
checkout fields later; submit a new managed proposal instead.

## 9. Approve in AG Pay, then approve in Link

This is deliberately a **double-approval** test; neither approval replaces the
other.

1. In AG Pay, open **Approvals** and inspect the exact merchant, item, quantity,
   total, currency, product URL, and checkout target. The checkout mode must be
   managed `stripe-hosted`. If it says **Legacy external completion**, do not
   approve it expecting a payment; create a new proposal whose OpenClaw tool
   call includes both explicit checkout arguments.
2. Select the assigned Stripe Link method and approve the proposal once.
3. The API atomically creates one queued checkout execution. The worker creates
   a **test-mode** Link SpendRequest bound to the approved merchant, amount,
   currency, line item, execution, and selected `csmrpd_...` method.
4. Open the Link notification. Recheck the merchant and total, then approve it.
   Link allows 10 minutes for this second approval.
5. Leave the worker running. It obtains the one-time test credential through a
   private `0600` file, opens the already-approved full Stripe Checkout URL,
   fills it through Browserbase, and follows the success redirect. The
   `letyouragentspay.com` server verifies complete/paid status plus the offer,
   amount, and currency with Stripe. The worker accepts only its visible
   `#agpay-payment-verification[data-agpay-payment-status="verified"]` receipt
   when the session/order reference matches the `cs_test_...` ID frozen from
   the approved URL.

Do not approve twice, restart the worker during submission, manually retrieve
the card, or retry a checkout whose submission may already have happened.

## 10. Verify the result

A successful run provides all of this evidence:

- **Approvals:** the item moves to purchased and its execution timeline reaches
  `succeeded`;
- **Purchases:** one purchase exists for the selected offer's exact approved
  amount and currency, attributed to the correct agent and payment method;
- **Stripe Dashboard, test mode:** the Checkout Session/PaymentIntent has the
  selected offer amount and a successful test status;
- **Link:** the SpendRequest was approved in test mode; the underlying saved
  card has no charge; and
- **worker/API logs:** no PAN, CVC, Link token, Link auth-file contents,
  `csmrpd_...` value, AG Pay bearer token, or Browserbase CDP URL appears.

The hosted fixture relies on the landing server's Stripe-verified paid-session
receipt, not an order at the proposal's `product_url`. A redirect or
Browserbase session alone is not payment proof.

## Troubleshooting

### Link CLI is missing or has the wrong version

Run `command -v link-cli` and `link-cli --version` from the same environment as
the worker. Reinstall `@stripe/link-cli@0.12.0`; do not silently accept a newer
JSON schema.

### Link reports unauthenticated or cannot refresh

Run `link-cli auth status` against the exact owner auth file. If necessary,
repeat `auth login` for that file. An auth file for one AG Pay owner must never
be copied or selected for another owner.

### No `csmrpd_...` method appears

The authenticated US Link account needs an eligible saved card. Add or verify
the card in Link, rerun `payment-methods list`, and copy only its opaque ID and
safe display metadata. Non-US Link accounts are not currently supported.

### Approval expires or is denied

The Link approval window is 10 minutes. A denied or expired SpendRequest does
not release a credential. Let the execution fail safely, inspect its timeline,
and create a new cart proposal only if the original never reached submission.

### AG Pay says the payment provider is unsupported

Check that the Link feature and test mode are enabled in the worker's
environment, the stored provider is exactly `stripe_link`, the reference
matches `csmrpd_...`, and the proposal uses the built-in `stripe-hosted`
adapter. Restart the API and worker after changing `.env`.

### Browserbase or Stripe test checkout fails

Confirm the Browserbase project/region, the complete offer-specific
`cs_test_...` URL including its fragment, and the landing site's server-side
Stripe test configuration. The worker itself needs no Stripe key, local
merchant, publishable key, tunnel, or port `8100`.

### Execution is `action_required`

On the fixed hosted rail, a challenge observed after browser submission is not
classified as `action_required`; without the verified success receipt it ends
as `outcome_unknown`. An `action_required` result can still come from a
separate pre-submit Link-consent or configured-adapter boundary. AG Pay does not
let an LLM solve 3-D Secure, CAPTCHA, or another interactive challenge.

### Execution is `outcome_unknown`

Do not retry. Check the Stripe test session in the landing deployment's Stripe
account and reconcile the landing verification result first. The no-retry rule
protects against duplicate submission when a browser or verification response
is lost after the irreversible boundary. A decline, 3DS challenge, timeout, or
any other non-success hosted result after submission belongs in this state.

## Stop and disconnect safely

Stop the API, web app, and worker with `Ctrl-C` in their terminals. Preserve
local database volumes:

```bash
cd /Users/vitaliibulyzhyn/Desktop/ag-pay
make infra-down
```

To revoke the local Link CLI session, point logout at the exact owner file:

```bash
link-cli auth logout --auth /absolute/private/path/to/the-owner-auth-file
```

## Production gates

This implementation is a test integration, not authorization to enable real
money:

- Link's agent wallet is currently available only to US Link accounts, not
  every Visa or Mastercard holder worldwide.
- AG Pay supports only reviewed checkout adapters and origins. A Link virtual
  card does not make Browserbase a universal buyer and does not bypass merchant
  terms, bot controls, CAPTCHA, issuer declines, or 3-D Secure.
- The test flow intentionally requires both AG Pay approval and Link approval.
  Do not switch to delegated `--approval-detail` until Stripe has approved the
  product model and the recorded AG Pay consent satisfies the provider,
  regulatory, and audit requirements.
- Production needs a separately isolated worker identity and filesystem,
  secret-manager-backed Link sessions, strict egress, complete redaction,
  access auditing, credential-file lifecycle management, PCI review, provider
  approval, and incident procedures.
- Reconciliation must cover successful authorization and later capture,
  clearing, refunds, disputes, cancellations, and `outcome_unknown`; merchant
  page text or a Link approval alone is not settlement proof.
- Link CLI, Link Pay Token, and machine-payment support evolve independently.
  Pin versions, inspect current official schemas, and regression-test every
  upgrade before changing the worker contract.

For a production managed-spend rail today, retain the separately documented
Stripe Issuing design and issue a dedicated, issuer-controlled virtual card per
approved execution.
