# Product scope

## Product statement

AG Pay is an agent-wallet control plane for purchases initiated by AI agents. A
person connects OpenClaw-like agents, adds provider-referenced payment methods
or a feature-gated local research card with personal/business billing
information, assigns allowed cards to agents, configures review, and retains an
attributable history of proposals, purchases, and subscriptions.

The first release is **supervised autonomy by default**: the agent researches
and proposes, and every new agent initially requires human approval. An owner
can opt individual agents into limited server-side automatic approval rules.
For proposals that explicitly name an operator-configured adapter and checkout
URL, approval can queue the narrow Browserbase + Stripe Issuing path or the
development-only hosted Stripe test proof. A third, disabled-by-default
`local_direct_card` rail stores an owner-scoped encrypted PAN and accepts CVC
only with human approval for an explicit direct research adapter. OpenClaw must
pass both managed fields because neither plugin nor playground supplies
defaults. Older/direct API proposals without both fields retain legacy
agent-reported sandbox completion: approval queues no payment. None of these
paths turns an arbitrary source URL into a merchant order. AG Pay is not a card
issuer, production card vault, bank, merchant of record, acquirer, or universal
payment executor.

## Problem

General-purpose agents can research products and navigate merchant sites, but purchasing introduces several unresolved questions:

- How does a person know which agent installation is connected?
- Which payment method may each agent use?
- What exactly is the agent buying, from where, and why?
- Who authorizes the spend before it occurs?
- Which proposals may follow a user-configured rule instead of interrupting the user?
- Which agent and card were responsible for a completed purchase?
- Which purchases created monthly or yearly commitments?
- Which merchant login can the human use after the purchase?

AG Pay answers these with explicit pairing, card assignments, fail-safe per-agent review policies, inspectable cart states, agent/card attribution, encrypted per-purchase merchant credentials, and purchase/subscription history.

## Actors

### Platform user

The human owner registers with username and password, creates/revokes agents, attaches cards, supplies personal or business billing information, assigns cards, configures each agent's approval policy, approves/cancels proposed items, reveals merchant credentials after password confirmation, and reviews proposed, approved, and historical items.

A platform email is not required in the prototype. Merchant account email is a different concept and belongs to a purchase credential.

### Agent

An OpenClaw-like process is paired to exactly one platform user. It heartbeats, proposes cart items with product/rationale/account details, reads its proposals, and receives sanitized managed-checkout outcomes. A gated legacy tool can still record an already-confirmed sandbox result for proposals with no managed execution. It cannot configure its policy, call the human approval endpoint, choose an automatic approval card, manage cards, reveal credentials through the human endpoint, control the payment worker, or access another agent's data.

### Payment provider or issuer

A third party normally tokenizes/issues cards and owns the durable raw-card-data
boundary. The configured-merchant worker retrieves a Stripe Issuing card only
into transient memory; the hosted proof materializes fixed public test values
inside the trusted worker. The local research exception stores PAN only as
tenant-scoped Fernet ciphertext. Its CVC is never durable: the human provides it
at approval and the worker consumes it once from short-lived memory. Production
still requires provider-hosted onboarding.

### Operator

A developer/operator maintains the API, PostgreSQL, and Redis. Operator access is not a public v1 role and must not become an unaudited tenant-bypass mechanism.

## Prototype capabilities

### Account authentication

- Register and log in with a unique normalized username and password.
- Hash passwords with a memory-hard algorithm.
- Issue a short-lived typed human access token.
- Scope every human-owned resource to the authenticated user.
- Keep the web session token in a server-managed HttpOnly, same-site cookie rather than browser JavaScript storage.

The web app can sign out by clearing its local session cookie. The backend does not yet have refresh sessions, access-token revocation, recovery, verified email, or multifactor authentication.

### Web management UI

- Register, log in, and sign out through the Next.js backend-for-frontend.
- Review an overview with setup progress, connection health, pending decisions, and recent purchases.
- Create, re-pair, and revoke agents; display one-time pairing tokens and poll for a successful handshake.
- Inspect compact OpenClaw/Hermes runtime cards and open a detail sheet for health, capabilities, assignments, re-pairing, and revocation.
- Add safe sandbox/provider payment-method metadata or, when explicitly
  enabled locally, enroll encrypted PAN without CVC; view only masked cards and
  manage agent/card assignments.
- Configure each agent's review policy on `/rules`.
- Review proposed, approved, purchased, and cancelled cart items; approve or
  cancel proposals; inspect managed status timelines and active Browserbase
  sessions; receive terminal outcome toasts; and reveal a merchant credential
  after password confirmation.
- Browse attributed purchases and recurring subscriptions and maintain locally tracked subscription status.
- Adapt the management shell and entity views to desktop and mobile browser widths.

The browser-facing routes proxy an explicit allowlist of human API operations. Agent handshake, heartbeat, proposal, legacy completion, direct item read, and checkout-event routes remain agent-to-FastAPI calls and are not exposed by the human web proxy.

### Agent management and connectivity

- Create, list, inspect, re-pair, and revoke agents.
- Return a short-lived one-time pairing token only when created/rotated.
- Exchange the pairing token for a hashed-at-rest opaque agent token.
- Record instance ID, software version, and capabilities.
- Refresh a Redis presence TTL through heartbeat and retain `last_seen_at`.
- Display `pending`, `online`, `offline`, or `revoked` connection state derived from `last_seen_at` in the current serializer.
- Build, install, and verify the AG Pay plugin inside the Dockerized OpenClaw
  playground for local integration testing.

The single-step token exchange proves possession of the pairing secret. Signed challenge-response pairing is planned hardening.

### Payment methods and billing information

- Attach provider-tokenized card references through the normal endpoint.
- In development/test only, accept a validated PAN through a separate local
  direct-card endpoint and store only dedicated-key ciphertext.
- Accept CVC only with human approval of one local direct managed execution;
  keep it only in the worker's TTL-bound one-shot memory broker.
- Store safe display metadata: name, provider, brand, last four, and expiry.
- Accept personal billing details: name, email/phone, and address.
- Accept business billing details: legal/contact names, VAT number, registration number, email/phone, and address.
- Disable methods without deleting historical purchase attribution.

Billing data is embedded on each payment method in the prototype. Reusable billing-profile resources are a future normalization option.

### Agent/card authorization

- Assign one or more active payment methods to an agent.
- Assign one payment method to multiple agents.
- Idempotently repeat assignment.
- Remove assignments at any time.
- Revalidate active assignment at cart approval, managed execution, and legacy completion.

### Per-agent payment policy

Every new agent receives an `always` policy. A missing legacy policy also fails safe as `always`, and listing policies backfills the default record. The owner can select one of five modes:

| Mode | Human review behavior |
| --- | --- |
| `always` | Every proposal requires review. This is the default. |
| `subscriptions_only` | Monthly/yearly proposals require review; one-time proposals are eligible for automatic approval. |
| `above_amount` | A proposal requires review only when its total is strictly greater than the configured threshold. Recurrence alone does not change the result. |
| `subscriptions_or_above_amount` | Monthly/yearly proposals or totals strictly greater than the threshold require review. |
| `never` | The policy does not request human review for any proposal. |

These mode descriptions apply to unmanaged legacy proposals. A proposal with
managed checkout fields always requires human approval, regardless of mode.

Thresholds contain a non-negative fixed-precision amount and uppercase three-letter currency. The comparison uses `unit_price × quantity`; a total exactly equal to the threshold does not require review. A proposal in a different currency always fails safe to human review because the prototype does not convert currencies.

Automatic approval applies only to an unmanaged legacy proposal and is
conditional on an active payment method assigned to the agent. A proposal with
managed checkout fields always remains `proposed` until the human selects an
assigned method supported by that adapter; that approval queues its execution
atomically.

`never` means “do not pause an unmanaged legacy proposal for human review.” It
is not an unlimited issuer permission, does not apply to managed checkout, and
cannot queue a worker execution.

### Purchase credential

- Require every agent cart proposal to include merchant account email and password, plus optional login URL.
- Encrypt the merchant password at rest.
- Hide the password from normal cart/purchase responses.
- Let the human reveal it only after supplying the current platform password.

The prototype uses a distinct credential per cart item, avoiding accidental cross-merchant password reuse.

### Cart and decision

- Let an authenticated agent propose title, description, product URL, optional merchant, reason, quantity, unit price, currency, recurrence period, merchant account, and, when managed execution is intended, an explicit configured checkout adapter/URL pair.
- Evaluate the originating agent's owner-configured payment policy when the proposal is stored.
- Present proposed, approved, purchased, and cancelled items to the user in review/history queues.
- Let only the human owner use the manual approve endpoint for a proposed item and select a currently assigned card.
- Let only the human owner cancel a proposed item.
- Preserve decision note and timestamp.
- Atomically queue one managed checkout on approval and recheck the selected method and exact amount/currency before execution.
- Persist `queued`, `running`, `succeeded`, `failed`, `action_required`, or `outcome_unknown` without unsafe post-submit retries.

### Purchase and subscription history

- Attribute each purchase to one source cart item, agent, user, and payment method.
- Record amount, currency, provider/order reference, optional receipt URL, and purchase time.
- Enforce at most one purchase per cart item.
- Create a subscription when the proposal is monthly or yearly.
- List subscriptions and maintain their local `active`, `paused`, or `cancelled` status and next billing time.

Changing local subscription status does not execute a merchant cancellation.

## Core journeys

### Connect an agent

1. The user creates an agent record.
2. AG Pay displays a pairing token that expires soon.
3. The user supplies that token to the intended agent runtime.
4. The runtime calls the handshake with installation metadata.
5. AG Pay consumes the pairing token, returns an agent token once, and shows the agent online.
6. Heartbeats maintain presence; a stale agent is shown offline but remains enrolled.

### Add and assign a card

1. In the normal web form, the user supplies an opaque provider reference and
   safe display metadata; PAN and CVC fields do not exist.
2. For configured-merchant managed sandbox checkout, the reference is a Stripe
   Issuing `ic_...` identifier. For the development-only `stripe-hosted` proof,
   the seeder creates safe `pm_stripe_demo_*` fixture references. Provider-hosted
   onboarding remains required before production use.
3. As a separate local research branch, the feature-gated direct-card form
   sends PAN, expiry, and billing details—but no CVC—to FastAPI. It derives safe
   metadata and stores only an opaque `ldc_...` method plus owner-scoped
   encrypted PAN.
4. The user assigns the method to one or more agents. A local direct method is
   never automatically selected and is valid only for managed checkout.
5. AG Pay prevents approval/completion after the card is disabled or unassigned.

Use provider sandbox references or a controlled local direct-card experiment
until provider onboarding, PCI, security, and compliance gates are complete.
The local rail is not production onboarding or universal merchant support.

### Configure an approval rule

1. The user opens `/rules` and sees every owned agent with its current mode; a missing legacy record is shown/backfilled as `always`.
2. The user chooses one of the five modes and, for an amount mode, supplies a threshold amount and currency.
3. The UI explains that “above” is strict, different currencies require review, and automatic approval still requires an active assigned card.
4. FastAPI verifies agent ownership and stores the rule. Future proposals use it; existing proposed/approved items are not retroactively reclassified.

### Decide, execute, and record a purchase

1. A paired agent submits a cart item and unique merchant login. For managed
   execution, the same OpenClaw tool call explicitly includes
   `checkout_adapter` and `checkout_url`; the integration does not fill them
   from defaults.
2. AG Pay calculates the total and evaluates the agent's review mode, recurrence, and threshold currency/amount.
3. If review is required—or no active assigned card is available—the item remains `proposed`; the user reviews its facts and selects an assigned card to approve, or cancels it.
4. If review is not required and an active assigned card exists, AG Pay records the item as `approved` immediately. The user can still inspect it in the Approved queue.
5. For a managed proposal, approval and one durable `queued` execution commit
   together. Approval of a legacy proposal without both managed fields records
   only a decision. The worker leases the job, revalidates tenant/assignment,
   origin, exact product, quantity, and total, and opens a non-recorded
   Browserbase session.
6. On Stripe Issuing it retrieves the tenant-bound virtual card just in time
   and correlates merchant success with an exact issuer authorization. It
   persists the irreversible boundary before the first card-field fill and
   never retries automatically after that boundary.
7. AG Pay transactionally creates the one-time managed purchase and sanitized terminal agent event. Legacy confirmed recurring proposals may still create a locally tracked subscription. OpenClaw polls managed events by durable cursor and wakes the originating session with a fixed safe message.
8. A definite pre-submit failure, interactive challenge, or ambiguous post-submit result becomes `failed`, `action_required`, or `outcome_unknown`. A legacy proposal can still use the gated external sandbox result endpoint.
9. The user sees the state in approvals and purchase/subscription history and can reveal the merchant login with current-password confirmation.

The current OpenClaw tool rejects a missing or partial checkout pair before
contacting AG Pay. Existing legacy items can originate from earlier plugin
versions or direct API clients; checkout fields cannot be attached to them
after creation, so the agent must submit a new managed proposal.

For the development-only `stripe-hosted` proof, steps 5–6 substitute a
proposal-supplied, offer-specific Stripe test Checkout Session URL and built-in
fake card fixture. The worker opens that existing URL, validates the displayed
offer facts, fills Stripe's publicly hosted page through Browserbase, and
accepts success only after the allowlisted landing server verifies the paid
session with Stripe and renders a matching receipt contract. The worker does
not create or poll the session and needs no Stripe credential. The web shows
every durable status transition plus a terminal toast, and the same sanitized
terminal event wakes the originating OpenClaw session. This proves the control
and notification loop, not an order at the proposal's source URL. On this
keyless rail, every non-success result after submission is
`outcome_unknown` for manual reconciliation; only the verified landing receipt
can establish success.

For `local_direct_card`, human approval also carries a fresh three- or
four-digit CVC. FastAPI stages it through an authenticated private Unix socket
in worker-owned memory; it is bound to the execution/owner/method and consumed
once before its short TTL. CVC is never in PostgreSQL, Redis, a file, logs, or
events. Before decrypting PAN or taking CVC, Stagehand uses Browserbase
`observe` only to identify empty payment/billing/submit controls. The worker
validates and freezes those selectors, then fixed native JavaScript and
Playwright perform every fill and click. The model neither sees values nor acts
on the page. Direct success requires the configured merchant success marker and
order reference, but that merchant-observed result is not issuer authorization,
settlement, or clearing proof.

## Acceptance criteria for the prototype

- A user can register, authenticate, and read only their resources.
- A user can perform the human management journeys through the web UI without exposing the FastAPI bearer token to browser JavaScript.
- A user can pair an agent with a single-use expiring token and see online/offline heartbeat state.
- A user can add both personal and business provider-referenced methods and can
  enroll a local encrypted-PAN method only when the research feature is enabled.
- One card can be assigned to multiple agents and one agent to multiple cards.
- An agent can propose a complete cart item including rationale and merchant login.
- Every OpenClaw managed purchase call explicitly supplies its adapter and
  checkout URL; the plugin and playground do not inject defaults.
- An agent cannot use human approval endpoints.
- A user can configure all five review modes independently per owned agent, while another user's policy remains inaccessible.
- Missing policies and threshold-currency mismatches require human review.
- Amount modes use total price and a strict greater-than comparison, so a total equal to the threshold is eligible for automatic approval.
- A policy-eligible unmanaged proposal becomes `approved` only with an active
  assigned method; every managed proposal remains `proposed` until human
  approval.
- Approval rejects a card not assigned to the proposal's agent.
- Disabling/unassigning the card after approval prevents completion.
- Purchase completion requires the exact proposed amount/currency and can create only one purchase.
- Managed approval creates only one durable execution; concurrent workers claim it once.
- Approval of a legacy item creates no checkout execution, and an existing
  legacy proposal or approval cannot be upgraded without a new proposal.
- The hosted test proof uses the approved offer's complete pre-existing Stripe
  Checkout Session URL, preserves its fragment, requires a matching
  server-verified paid-session receipt, and never represents that result as an
  order from the source product URL. A single fixed URL cannot represent
  multiple offers, and a submitted non-success result is always
  `outcome_unknown` rather than an inferred decline or challenge.
- Configured Issuing and local direct Browserbase sessions disable recording,
  logging, CAPTCHA solving, and persistent context. The hosted public-fixture
  proof intentionally records/logs its test-only session for replay.
- Local direct form analysis is observe-only, occurs before secrets are loaded,
  persists selectors only, and leaves every mutation/click to deterministic
  JavaScript/Playwright.
- Managed execution never automatically retries after `submitted_at`; ambiguous outcomes are visible to the user and agent.
- OpenClaw receives a sanitized terminal event routed to the originating session without any Browserbase/provider/card secret.
- Completed one-time purchases and monthly/yearly subscriptions can be listed with agent/card attribution.
- Merchant passwords are encrypted and excluded from ordinary responses.
- Cross-user/agent negative tests demonstrate tenant isolation.
- The normal provider endpoint rejects PAN/CVC-shaped input. The local direct
  endpoint stores PAN only as owner-scoped ciphertext and never returns or logs
  it. CVC is accepted only at direct approval and is never persisted, logged,
  published to Redis, or supplied to the model.
- Local direct success is explicitly merchant-observed research evidence, not
  issuer authorization; any ambiguous post-submit outcome is
  `outcome_unknown` with no automatic retry.

## Explicit non-goals for the managed-checkout prototype

- Card issuance, money custody, balances, transfers, acquiring, or settlement.
- Giving a language model raw PAN, CVC, PIN, or 3-D Secure secrets.
- Provider webhook ingestion, refunds, disputes, chargebacks, or settlement reconciliation.
- Automatic retry or automatic resolution of an ambiguous post-submit checkout.
- Universal arbitrary-site checkout, LLM page actions, unvalidated selector
  execution, or treating a review threshold as a real issuer spend cap. The
  local experiment permits observe-only selector proposals before secrets,
  followed by validation and deterministic execution.
- Issuer-enforced per-purchase limits, cumulative budgets, risk scoring, or organization-wide policy inheritance.
- Immutable merchant SKU/variant binding for catalogs where title and price are
  not unique.
- Team accounts, roles, delegated approval, enterprise SSO, or recovery.
- Durable event/audit pipeline; Redis Stream events are best effort.
- Mobile application and a broader public SDK beyond the initial `ag-plugin-openclaw` integration.

## Production gates and next phases

The delivery sequence is:

1. Retain the implemented Stripe Playground (`stripe-hosted`) as the visual,
   end-to-end development proof.
2. Retain `local_direct_card` only as the implemented, feature-gated research
   proof of encrypted PAN, approval-time ephemeral CVC, observe-only mapping,
   and deterministic injection. Do not present its merchant-page result as
   issuer proof or enable it outside development/test.
3. Broaden and harden the current narrow configured-merchant/Stripe Issuing
   path so reviewed adapters can inject provider-issued, short-lived payment
   credentials directly into allowlisted merchant forms without exposing them
   to the model or control plane.
4. Add provider adapters for Visa and Mastercard agent-commerce capabilities,
   subject to access, onboarding, certification, regional availability, and
   compliance review. These adapters should use provider-hosted enrollment,
   authenticated bounded instructions, network controls, and outcome signals;
   AG Pay must continue to store only opaque references and safe metadata.
5. Extend the same provider-neutral boundary to additional issuers, wallets,
   PSPs, merchant APIs, and agent ecosystems.

Steps 3–5 are roadmap work. The implemented research rail in step 2 is not a
claim of universal merchant coverage, network approval/endorsement, or
production availability.

Before real autonomous purchasing:

- choose a PSP/issuer and complete its security/compliance onboarding;
- use hosted card collection and verify provider metadata server-side;
- issue per-agent or preferably per-approved-purchase virtual cards/authorizations;
- replace review-only policy thresholds with bounded execution grants containing an issuer-enforced amount ceiling, merchant origin, recurrence, expiry, and attempt count;
- add idempotency, execution leases, `unknown` reconciliation state, durable outbox/audit events, and verified webhooks;
- move merchant secrets to managed storage and add durable reveal/usage audit;
- shorten/rotate agent credentials and add signed proof-of-possession pairing;
- add user recovery, session revocation, step-up authentication, notifications, monitoring, and incident procedures.

Later product work can add organizations and approval chains, merchant/category and cumulative-budget policies, refunds/disputes, accounting integrations, receipt capture, merchant-confirmed subscription cancellation, a mobile client, the developer SDK, and further payment ecosystems after their individual security and compliance gates are satisfied.
