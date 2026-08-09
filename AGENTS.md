# Development agent guide

## Repository boundary

This base repository owns shared documentation and local infrastructure only.
Repositories below `dev/` are independent Git repositories and are intentionally
ignored here. Do not stage their files in the base repository or turn them into
submodules unless the project owner explicitly changes the repository model.

The current child repositories are:

- `dev/ag-pay-platform`: FastAPI backend and Next.js web application monorepo;
- `dev/mobile`: placeholder for the future mobile application;
- `dev/ag-plugin-openclaw`: OpenClaw plugin package;
- `dev/ag-openclaw-playground`: Dockerized OpenClaw runtime with the sibling AG Pay
  plugin built and installed automatically.

The canonical runnable child repositories are `ag-pay-platform`,
`ag-plugin-openclaw`, and `ag-openclaw-playground`. The mobile directory remains
a future placeholder and an agent must not invent a remote for it.

## Full local development bootstrap

When the user asks to "follow the guide and set up my entire development
environment," carry out this workflow from the base-repository root. Setup is
complete only when every required component passes its documented checks or
is clearly reported as requiring user input.

1. Read this file and each cloned child repository's `AGENTS.md`. Inspect the
   Git status of the base and every child before changing anything. Preserve
   the repository boundary: never stage child files in the base repository,
   convert children to submodules, reset them, or discard their changes.
2. Check for Git, Docker with Compose v2, Make, Python 3.12, Node.js 24.15.x,
   and pnpm 11.9.0. Node 24.15.x satisfies both the web and plugin constraints.
   Check whether ports `3000`, `5050`, `5432`, `6379`, `8000`, and `18789` are
   already in use. Report missing or incompatible tools; do not replace global
   tooling or kill existing processes without the user's approval.
3. Ensure `dev/` exists. Clone a missing platform from
   `https://github.com/AG-Pay-Labs/ag-pay-platform.git` into
   `dev/ag-pay-platform`, and a missing plugin from
   `https://github.com/AG-Pay-Labs/ag-plugin-openclaw.git` into
   `dev/ag-plugin-openclaw`. Clone a missing playground from
   `https://github.com/AG-Pay-Labs/ag-openclaw-playground.git` into
   `dev/ag-openclaw-playground`. If a destination exists, require it to be a
   Git worktree and verify its `origin`; do not overwrite or pull it
   automatically. If both a canonical directory and its legacy `ag-platform`
   or `ak-kit` directory exist, stop and report the conflict. Rename a legacy
   directory only when the canonical destination is absent.
4. Create environment files only when absent. Run `make init-env` at the base
   root. In `dev/ag-pay-platform`, copy `.env.example` to `.env` and
   `apps/web/.env.example` to `apps/web/.env.local` only if each destination is
   missing. Never print or overwrite secret values. Keep the root PostgreSQL
   and Redis credentials aligned with the API connection URLs.
5. From the base root, run one command at a time: `make infra-check`,
   `make infra-up`, and `make infra-ps`. Require PostgreSQL, Redis, and pgAdmin
   to become healthy.
6. From `dev/ag-pay-platform`, run `make api-install`, `make api-migrate`,
   `make web-install`, `make lint`, `make test`, and `make web-build`.
7. From `dev/ag-plugin-openclaw`, run `make install`, `make check`, and
   `make pack-check`. These checks must not publish a package.
8. Start `make api-run` and `make web-run` from `dev/ag-pay-platform` in
   separate persistent terminal sessions. Verify the API liveness and readiness
   endpoints and load `http://127.0.0.1:3000/login`. If persistent sessions are
   unavailable, report the exact commands the user must run instead of hiding
   a background process.
9. From `dev/ag-openclaw-playground`, run `make init`, `make check`,
   `make smoke`, `make ps`, and `make dashboard`. Never print its `.env`,
   Gateway token, provider keys, pairing tokens, or AG Pay bearer tokens. Do
   not claim that a playground smoke check proves a purchase; it verifies the
   Gateway, plugin, and SecretRef surfaces.
10. Leave account creation, agent creation, provider-key entry, and pairing to
    the user. Pair only through the hidden `make pair` prompt. Never place a
    `pair_...` token in a command argument or ask the user to paste a provider
    key, `agt_...` token, password, or payment credential into chat.
11. Finish with a concise report of repository paths and remotes, detected tool
    versions, checks run, service health, local URLs, remaining human steps,
    and the non-destructive stop commands. Never delete Compose volumes as part
    of setup.

## Product and security invariants

- The platform is supervised autonomy in the prototype: an agent proposes and a
  human approves or cancels.
- Never accept, persist, log, return, or expose raw PAN, CVC, PIN, or 3-D Secure
  secrets to the API, web app, OpenClaw, an LLM, or ordinary telemetry. Managed
  checkout may retrieve an active virtual card only in trusted worker memory
  immediately before deterministic form filling. Payment methods remain
  provider references plus safe card metadata.
- Describe managed checkout narrowly and truthfully: production requires an
  explicitly configured merchant adapter plus Stripe Issuing reference; the
  separate Stripe Payments fixture rail is development/test-only.
  Legacy completion only records sandbox/external success; Browserbase alone is
  not a vault or a universal payment integration.
- Never automatically retry a checkout once submission may have occurred.
  Persist and surface `outcome_unknown` for manual reconciliation.
- Keep the human platform login separate from the encrypted merchant credential
  attached to each cart proposal.
- Every owned lookup must be tenant scoped. Every agent action derives identity
  from the agent token, never an ID in the request body.
- Label roadmap/hardened architecture separately from implemented behavior in
  documentation.

## Base-repository checks

Run `make infra-check` after Compose changes. When services are available, run
`make infra-up` and require PostgreSQL, Redis, and pgAdmin to become healthy.
Keep `.env` files and nested `dev/` repositories untracked.
