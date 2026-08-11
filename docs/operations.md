# Operations

## Environment progression

Use distinct development, test, staging, and production environments with separate databases, Redis instances, credentials, provider accounts, signing keys, and network policies. Never reuse sandbox provider credentials or local JWT keys in production.

The prototype's managed path integrates Browserbase with Stripe Issuing test or
virtual cards for explicitly configured merchants. Deployment alone does not
make that path production ready. Threat review, PCI/compliance assessment,
provider controls, secret management, monitoring, backups, and incident
procedures remain release gates.

The separate `stripe-hosted` proof is hard-gated to `development`/`test`. It
uses a Stripe test-mode secret and built-in fake-card fixtures to demonstrate
provider-verified outcomes. Never enable or describe it as a staging/production
merchant integration.

## Configuration and secrets

- Validate all required configuration at startup and fail with a clear, redacted error.
- Keep secrets out of Git, container images, Compose files, command history, and log output.
- Use asymmetric token signing where practical so API verification does not require distributing a signing secret.
- Rotate signing keys with key IDs and an overlap window.
- Rotate database, Redis, provider, webhook, and secret-store credentials independently.
- Namespace Redis keys by environment and application.

The Next.js service uses server-only `AGPAY_API_URL` to reach FastAPI. Keep it out of client-side environment namespaces. Its human JWT cookie is HttpOnly and same-site, and must be `Secure` outside local HTTP development. Responses from auth, proxy, and merchant-credential reveal routes use `Cache-Control: no-store`.

Web logout currently clears the browser cookie only. Because FastAPI access tokens are not yet revocable, operators must treat JWT-key rotation or account deactivation as the available emergency invalidation mechanisms until server-side sessions are implemented.

The OpenClaw playground is local development infrastructure, not a production
deployment. Keep its `.env`, Gateway token, provider keys, pairing tokens, and
agent bearer token untracked; bind its host port to loopback and store the AG
Pay token through the configured file-backed SecretRef.

Managed checkout is disabled by default. Its platform-only settings are:

- `CHECKOUT_ENABLED` and `CHECKOUT_ADAPTERS` for the feature gate and validated
  server-owned merchant/origin/selector definitions;
- `BROWSERBASE_API_KEY`, `BROWSERBASE_PROJECT_ID`, `BROWSERBASE_REGION`, and
  optional API URL for the isolated browser session;
- `STRIPE_SECRET_KEY` and optional API URL for virtual-card retrieval and
  authorization reconciliation; and
- worker poll interval, lease duration, pre-submit attempt limit, and result
  timeout.

The hosted proof additionally requires `CHECKOUT_DEMO_ENABLED=true`,
`CHECKOUT_HOSTED_DEMO_ENABLED=true`, and `STRIPE_DEMO_SECRET_KEY=sk_test_...`.
It installs a pinned `stripe-hosted` adapter and does not require a
`CHECKOUT_ADAPTERS` entry, Stripe publishable key, local merchant, tunnel, or
port `8100`. Those demo flags fail startup outside development/test.

Never copy these provider secrets into the web application or OpenClaw
playground. Only the checkout worker should receive them from a deployment
secret manager; the web-facing API process must use a separate environment and
secret mount.
See [Managed checkout](./managed-checkout.md) for the exact local contract.

## Health and readiness

`/health/live` proves only that the process event loop responds. In `0.1.0`, `/health/ready` executes a PostgreSQL query and Redis `PING`; either dependency failing returns `503`. It does not currently check Alembic schema compatibility.

Do not expose configuration values, hostnames, stack traces, dependency versions, or credentials through health endpoints.

The web service does not yet have a dedicated readiness route. Deployment health should verify that the Next.js process can serve a public page and separately monitor FastAPI `/health/ready`; a rendered login page alone does not prove that PostgreSQL, Redis, or the backend origin is reachable.

## Observability target

The prototype publishes a capped, best-effort Redis Stream and logs broker
failures. Managed checkout additionally writes one durable terminal
`CheckoutEvent` in PostgreSQL for agent delivery and ordered
`CheckoutStatusTransition` rows for the human lifecycle view. These records do
not contain full actor, DOM, issuer, or reconciliation evidence and are not a
complete audit ledger. The structured request logs, metrics, tracing, durable
audit, dashboards, and alerts below are production requirements, not currently
complete features.

### Structured logs

Every request log includes timestamp, level, environment, request/correlation ID, route template, status, duration, and authenticated actor type/ID when safe. Use route templates rather than full URLs to avoid leaking identifiers and query secrets.

Security/business events should include pairing created/exchanged/failed, credential rotated/revoked, payment method attached/disabled, assignment changed, payment policy changed, policy/manual approval source, cart proposed/approved/cancelled, purchase completed/failed/unknown, purchase credential revealed/rotated, and provider webhook accepted/rejected.

Next.js access and error logs must also redact cookies, authorization headers, request bodies, platform passwords, merchant credentials, pairing tokens, and provider references. Log route templates and correlation IDs rather than full resource URLs where practical.

### Metrics

Track at minimum:

- request rate, latency, and error rate by route/status;
- PostgreSQL pool use, query latency, lock waits, and migration version;
- Redis latency/errors and rate-limit activity;
- login and pairing failure rates;
- online/offline agent counts and heartbeat lag;
- pending cart-item age and approval decision time;
- policy mode counts, automatic-versus-manual approval rates, fail-safe currency/no-card fallbacks, and changes to permissive modes;
- purchase begin/completion/failure counts;
- managed executions by safe state, pre-submit retries, expired leases,
  `action_required`, and `outcome_unknown` reconciliation backlog;
- webhook verification failures and reconciliation backlog.

Metrics labels must not contain usernames, URLs, merchant-account emails, tokens, or unbounded resource IDs.

### Tracing

Trace IDs may connect API, worker, database, and provider operations. Spans must redact request bodies and secrets. Cart-item and purchase IDs can be recorded only under the project's data-handling policy.

## Required durable audit log

`0.1.0` does not yet persist `AuditEvent`; its Redis Stream is best effort. Before production, financial and security audit events must become durable PostgreSQL records separate from operational logs. They should be append only to application roles, carry actor and outcome, and use redacted structured details. Establish retention and export controls before production.

Application audit logs do not replace provider settlement records or a financial ledger. If the platform later holds funds or becomes merchant of record, it needs double-entry accounting and substantially different controls.

## Backups and recovery

- Enable encrypted automated PostgreSQL backups and point-in-time recovery in production.
- Store backups in a separate failure domain with tightly restricted access.
- Define recovery point and recovery time objectives before launch.
- Test restoration regularly; an untested backup is not a recovery plan.
- Redis is not backed up as the business system of record. Reconstruct queues/locks from PostgreSQL state where possible.
- Preserve migration versions and application artifacts needed to restore a compatible release.

## Database operations

- Run migrations as a controlled deployment job before shifting traffic.
- Favor expand/migrate/contract changes compatible with rolling deployments.
- Monitor long transactions and row locks around purchase state transitions.
- Use least-privilege roles: application runtime, migration job, read-only support/analytics, and backup roles are distinct.
- pgAdmin is disabled in shared/production environments unless there is a separately secured administrative need.

## Alerts

Initial actionable alerts should cover:

- sustained API unavailability or high server-error rate;
- PostgreSQL unreachable, storage nearing capacity, or exhausted connection pool;
- Redis unavailable for security-sensitive workflows;
- migration/schema mismatch;
- spike in failed logins, pairing claims, or webhook signatures;
- duplicate/conflicting execution attempts;
- managed executions stuck in `running` beyond their lease or any unexpected
  replay after `submitted_at`;
- backup or restore-verification failure;
- abnormal rate of secret reveal or agent revocation;
- unexpected automatic-approval volume, repeated no-card fallback, or a spike in agents using `never` review.

Every alert needs an owner and a short runbook link. Avoid alerts that reveal user or payment data in third-party paging systems.

## Incident basics

For suspected credential or payment compromise:

1. Preserve relevant audit evidence without copying secrets into chat or tickets.
2. Revoke affected user sessions, agent credentials, pairings, assignments, and provider tokens as appropriate.
3. Stop new purchase execution while retaining read access if safe.
4. Contact the provider/issuer and required internal security/compliance owners.
5. Reconcile requests, provider events, and merchant outcomes to find ambiguous charges.
6. Rotate affected infrastructure/application secrets.
7. Communicate with users and regulators according to the incident and applicable obligations.
8. Document causes and corrective actions after containment.

## Data lifecycle

Before real users, define deletion and retention behavior for platform accounts, embedded billing details, purchase credentials, purchase records, subscriptions, and future audit events. User-facing deletion may need to retain limited financial records for legal reasons; retained records should be minimized and access restricted. Removing a payment method or agent must immediately stop future use even when historical references remain.

## Deployment checklist

- Configuration validates and no development defaults remain.
- Database backup is current and the migration plan is reviewed.
- Migrations pass against a production-like snapshot.
- Health checks, dashboards, and alerts are active.
- Logs/traces have passed secret and card-data leakage tests.
- Cross-tenant and credential-audience tests pass.
- Provider webhook verification uses the deployed endpoint secret.
- Rollback or forward-fix steps are documented.
- Real payments remain disabled unless provider, issuer, security, and compliance gates are complete.
- Managed checkout runs as a separate worker deployment with the same schema
  version as the API, least-privilege network access, and no request-body or
  browser tracing.
- Browserbase session creation disables recording, session logging, and CAPTCHA
  solving; account access and Live View are restricted and audited.
- Every enabled adapter has reviewed exact merchant/payment origins and
  deterministic selectors. Wildcards and model-provided selectors are absent.
- An `outcome_unknown` reconciliation runbook and responsible operator exist;
  there is no automatic retry from that state.
- The Next.js `AGPAY_API_URL` resolves to the intended FastAPI deployment and is not bundled into client-visible configuration.
- Session cookies are HttpOnly, same-site, and `Secure`; BFF responses carrying account or purchase data are non-cacheable.
- The BFF route allowlist has been reviewed against the current human API and does not proxy agent credential or execution endpoints.
