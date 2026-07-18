# dapp — Best-Card Recommender

## LLM provider

All LLM code must be **model-agnostic**. Program against an abstract `LLMClient`
interface — never call a provider SDK directly from business logic. DeepSeek is the
current impl; other providers (incl. a local model for PII statements) must slot in
by adding a new impl only, with zero changes to callers. Provider + key come from
config/env, not hardcoded.

## Project

Personal, offline-first app: at point of payment, suggest which of the user's
credit cards gives the max reward for the spend category. Three components:
ingestion tool (Python + DeepSeek → SQLite), recommendation engine (Dart, pure
logic), mobile app (Flutter). See plan: full spec drives task breakdown.

## Working style

- TDD: write tests first, each task's suite must pass before it's done.
- Minimalistic code, standard libraries at latest versions, no speculative abstraction.
- Tasks built to run in parallel where independent.
