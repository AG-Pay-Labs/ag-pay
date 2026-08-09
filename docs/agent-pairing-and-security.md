# Agent pairing and security

## Security goals

Pairing binds a live agent installation to an agent record deliberately created by the owning user. The resulting agent credential is distinct from human authentication, revocable, and attributable on every agent action.

The prototype handshake proves possession of a short-lived, one-time pairing secret. It does not attest the agent software, prove the host is uncompromised, or provide cryptographic proof of possession after the bearer token is issued. Human approval is the default containment control; owners can deliberately narrow review with a server-evaluated per-agent policy. Those modes remain sandbox/control-plane features until issuer-enforced execution limits exist.

## Implemented prototype handshake

```mermaid
sequenceDiagram
    participant User
    participant API
    participant Agent
    participant DB as PostgreSQL
    participant Redis

    User->>API: POST /api/v1/agents
    API->>DB: Store hash(pairing token) + expiry
    API-->>User: Pairing token (shown once)
    User->>Agent: Transfer token out of band
    Agent->>API: POST /api/v1/agent/handshake
    API->>DB: Lock matching agent; verify token and expiry
    API->>DB: Consume pairing token; store hash(agent token)
    API->>Redis: Mark agent online with TTL
    API-->>Agent: Agent bearer token (shown once)
    Agent->>API: POST /api/v1/agent/heartbeat
    API->>DB: Update last_seen_at
    API->>Redis: Refresh online TTL
```

### 1. User creates an agent

An authenticated user calls `POST /api/v1/agents` with a name and optional description. The backend creates a `pending` agent and generates a `pair_...` token using cryptographically secure random bytes.

The raw token is returned only in the create response. PostgreSQL stores a keyed SHA-256 digest, expiry, and agent ownership. The default expiry is configurable and currently fifteen minutes.

### 2. User transfers the pairing token

The user gives the token to the intended OpenClaw-like runtime through an out-of-band channel. Treat it like a password until consumed: do not put it in URLs, screenshots, logs, committed configuration, or agent prompts retained by third parties.

If the token expires or may have leaked, `POST /api/v1/agents/{agent_id}/pairing-token` creates a replacement. Rotation invalidates unused pairing data and any previously issued agent token for that record.

### 3. Agent exchanges the token

The agent calls `POST /api/v1/agent/handshake` with the pairing token, an installation-specific `instance_id`, optional software version, and a bounded capabilities list.

The backend:

1. hashes the supplied token and selects the matching agent row for update;
2. verifies the agent is not revoked and the token is unexpired;
3. creates a random `agt_...` bearer token;
4. stores only the keyed digest and expiry of that token;
5. consumes the pairing token so it cannot be reused;
6. records installation metadata and connection time;
7. commits before reporting success;
8. marks the agent online in Redis and returns the bearer token once.

The default agent-token lifetime is currently one year. That is convenient for the prototype but too long without rotation and stronger endpoint controls in a real payment environment.

### 4. Agent maintains presence

The agent calls `POST /api/v1/agent/heartbeat` with its bearer credential. The backend updates durable `last_seen_at` and refreshes a Redis presence key. The default online window is two minutes.

The persisted enrollment state is `pending`, `active`, or `revoked`. The human API derives a display state of `pending`, `online`, `offline`, or `revoked`. Going offline is informational and does not erase the credential; revocation is explicit.

## Credential storage and validation

- User passwords use the password-hashing library's recommended memory-hard hash (Argon2 in the current dependency set), with a unique salt managed by the library.
- User access JWTs contain `sub`, `type=user`, issued time, and expiry. The `type` check prevents them from entering agent routes.
- Agent bearer tokens must have the `agt_` prefix and match a stored keyed digest for an active, unexpired agent.
- Pairing and agent token hashes are keyed with the application secret before hashing, reducing offline token verification if only the database leaks.
- Raw pairing/agent tokens must be redacted from logs, traces, analytics, and support artifacts.
- Deleting an agent marks it revoked and clears its pairing/token digests.

## Human authentication limits

The prototype registers with username and password only. It has no refresh sessions, logout revocation, multifactor authentication, verified recovery channel, or password-reset flow. Until those exist:

- access tokens should remain short lived;
- a lost password cannot be safely self-recovered;
- changing the JWT secret invalidates all user JWTs and also affects keyed token digests;
- production deployment must replace the symmetric development secret with managed key material and a planned rotation strategy.

Login should use generic failure messages and rate limiting. The code currently returns a generic invalid-credentials message but distributed brute-force controls remain a production gap.

## Authorization matrix

| Capability | Human owner | Paired agent | Anonymous/pairing context |
| --- | ---: | ---: | ---: |
| Register/login | Registration/login | No | Yes, only entry endpoints |
| Manage/revoke agents | Yes | No | No |
| Obtain/rotate pairing token | Yes | No | No |
| Exchange pairing token | No | Before bearer issuance | Valid one-time token only |
| Send heartbeat | No | Own identity | No |
| Manage/assign payment methods | Yes | No | No |
| Read/update per-agent payment policies | Yes | No | No |
| Propose cart item | No | Own identity | No |
| Approve/cancel cart item | Yes | No | No |
| Record legacy approved purchase | No | Originating agent only | No |
| Execute managed checkout | No | No; trusted platform worker only | No |
| Read sanitized checkout outcomes | No | Originating agent only | No |
| List all purchase history | Yes | No | No |
| Reveal purchase credential | Yes, with current password | No | No |

Every lookup is owner or agent scoped. Authorization must never rely on an owner/agent ID supplied in an untrusted request body.

## Purchase authorization controls

Human approval binds a managed cart item to one payment-method ID. A legacy
policy-derived approval can bind only an unmanaged proposal. Completion
rechecks that:

- the item belongs to the authenticated agent;
- its status is `approved`;
- the selected method is still active;
- the method is still assigned to the agent;
- final currency matches the proposal;
- final amount exactly equals `unit_price × quantity`;
- no purchase already exists for the cart item.

Only a human user can call the approve/cancel and policy-management endpoints.
During creation of an unmanaged proposal, FastAPI may apply the owner's stored
policy and select an active assigned card; the agent cannot supply the policy,
threshold, owner, or selected card. A proposal with managed checkout fields is
always `proposed` until that human endpoint approves it. Missing policy data,
threshold-currency mismatch, and absent active assignments fail safe to
`proposed`.

The `never` mode suppresses human review only for an unmanaged legacy proposal.
It never mints a managed execution, provider authorization, or unlimited
real-money permission.

Managed approval now freezes the exact amount/currency, normalized checkout
origin, selected method, adapter snapshot, and attempt limit into an execution
with a database lease and `outcome_unknown` safeguard. Before production
payments it still needs an expiry or quote window, an explicit all-in ceiling,
issuer-enforced merchant/amount controls, and stronger recurring terms.

## Purchase credential secrets

Each cart proposal contains the email/password the agent used or will use for that merchant purchase. The backend stores email and login URL as metadata and encrypts the password using Fernet.

The normal cart and purchase serializers expose only the email and login URL, never the password. Human reveal requires the current platform password and emits a best-effort broker event.

Prototype rules:

- Set a dedicated random `CREDENTIAL_ENCRYPTION_KEY`; do not rely on the development fallback derived from `JWT_SECRET`.
- Never put merchant passwords in logs, traces, analytics, error details, Redis events, or list/read responses.
- Add `Cache-Control: no-store` and durable reveal audit records before production.
- Prefer a unique generated password per merchant rather than reusing the user's personal password.
- Rotate or disable credentials independently when merchant access changes.

A managed secret store and short-lived, request-scoped secret lease are the production target. Application-level database encryption is useful defense in depth but does not protect secrets when the application runtime and its key are both compromised.

## Current pairing limitations

The bearer exchange is intentionally simple for the first prototype:

- no server nonce or challenge-response signature;
- no agent public key or device attestation;
- no proof-of-possession on later requests;
- no fine-grained agent scopes;
- no self-service agent-token rotation;
- no persistent pairing-attempt rate limiter yet.

These limitations are acceptable only with fake/sandbox payments and a controlled development environment.

## Hardened handshake path

The next protocol version should keep the one-time pairing token but add key possession:

1. The agent generates an Ed25519 keypair locally and sends the public key when claiming the pairing token.
2. The backend returns a single-use nonce, challenge ID, intended agent ID, server origin, and short expiry.
3. The agent signs a canonical encoding of that context.
4. The backend verifies and consumes both challenge and pairing token atomically.
5. Later requests use proof-of-possession signatures or very short-lived access tokens bound to the key.

The pairing response should show the human the installation metadata and requested capabilities. Protocol messages need an explicit version and canonical signing format.

## Threats and controls

| Threat | Current control | Required hardening |
| --- | --- | --- |
| Pairing token theft | Short expiry, one-time digest, rotation | Attempt limits, signed challenge, user confirmation/audit |
| Pairing replay | Token consumed atomically | Nonce and public-key proof |
| Agent token leak | High entropy, digest-only storage, expiry/revocation | Rotation, scopes, proof of possession, shorter TTL |
| Compromised agent | Default human review, owner-set policy, active assignment requirement | Issuer-enforced amount/merchant limits, risk controls, alerts |
| Agent self-approval/policy change | Policy management requires owner JWT; server evaluates stored policy and selects card | Automated audience/policy-integrity tests, durable audit, step-up for permissive modes |
| Cross-tenant IDOR | Owner-scoped queries | Systematic negative tests and database tenant invariants |
| Double purchase | Unique purchase per cart item | Idempotency record, execution lease, reconciliation/unknown state |
| SSRF from product URL | Backend does not fetch submitted URLs | Egress controls if fetching is added |
| Secret leakage | Encrypted password, redacted serializers | Central log redaction, managed secret store, durable audit |
| Redis loss | PostgreSQL remains business source of truth | DB-backed outbox/leases and recovery jobs |

## Minimum security test set

- Cross-user reads and mutations fail for agents, cards, cart items, purchases, subscriptions, and credentials.
- Human tokens fail on every agent endpoint; agent tokens fail on human endpoints.
- A pairing token works exactly once and fails after expiry or rotation.
- A revoked or expired agent token cannot heartbeat, propose, or complete.
- A disabled/unassigned payment method cannot be approved or used at completion.
- Cross-user payment-policy reads/updates fail, and agent tokens cannot manage policies.
- New/missing policies require review; amount equality, strict-greater totals, recurrence modes, and currency mismatch are tested.
- A policy-eligible proposal without an active assigned method remains proposed.
- Only the originating agent can complete its approved cart item.
- Concurrent completion attempts create at most one purchase.
- Merchant passwords never appear in standard serializers or event payloads.
- Logs are scanned for authorization headers, `pair_`/`agt_` tokens, password fields, PAN-like values, and CVC fields.
