# AG Pay

[![Status: Prototype](https://img.shields.io/badge/status-prototype-F59E0B?style=flat-square)](#what-we-are-building)
[![Autonomy: Human Supervised](https://img.shields.io/badge/autonomy-human_supervised-7C3AED?style=flat-square)](#what-we-are-building)
[![Security: No Raw Card Data](https://img.shields.io/badge/security-no_raw_card_data-0891B2?style=flat-square)](#what-we-are-building)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-16A34A?style=flat-square)](#help-build-the-payment-layer-for-agents)

![AI agents purchasing goods and digital services through AG Pay](assets/ag-pay-agent-commerce.png)

**A human-supervised payment control plane for AI agents.**

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
change how a proposal moves through AG Pay, but the platform does not currently
charge a card or execute a live payment; the agent completes checkout outside
AG Pay and reports the result. Live payment execution requires a future
issuer/provider integration.

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
