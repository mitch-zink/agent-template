# Agent Kit: Build Plan

A handoff for one engineer: about 25 working days from this design to an open-source v0.1 and a live Agents tab in a host app. Read [`architecture.md`](architecture.md) first. The reference sketches in [`reference/`](reference/) typecheck against the real packages and show every load-bearing call.

**Last updated:** 2026-10-06 · **Status:** design approved, not started

## Milestones

| # | Milestone | Days | Done when |
|---|---|---|---|
| M0 | Spikes | 1 | Approval round trip, Gateway cost field, MCP annotations, cron-to-Vercel all reconfirmed on current versions (already validated once; see architecture §12) |
| M1 | Repo restructure + schema | 2 | Template files move to `templates/personal-assistant/`; [`schema.sql`](schema.sql) becomes migrations; RLS tests pass for owner, team viewer, stranger; Supabase advisors show 0 security warnings |
| M2 | `packages/core` | 4 | A seeded agent answers through AI Gateway, calls an MCP tool, pauses on a write; Vitest suite green |
| M3 | `packages/vercel` routes + scheduler | 3 | `/turn`, `/decide`, `/tick`, `/run-routine`, `/runs` on a deployment; a minutely routine fires exactly once per minute for 10 minutes |
| M4 | `packages/react` Agents tab | 4 | List, agent page (Activity, Approvals, Schedule, Identity), builder, chat with approval cards; Playwright passes at 390px and 1280px |
| M5 | Templates + example app | 2 | 4 starter agents seed from `templates/`; `examples/vite-app` deploys from a clean clone in under 15 minutes |
| M6 | Real-run validation | 2 | Scenarios R1-R12 pass on a real Supabase + Vercel project, signed in as a real user |
| M7 | Host app adoption | 4 | Agents tab behind a flag in a real app, tools from that app's MCP, scenarios A1-A6 pass |
| M8 | Open-source launch | 2 | History scan clean, license + security docs, repo public, `v0.1.0` published |

## Success criteria

Measured on real runs, never mocks. Not measured = failed.

| # | Criterion | Target |
|---|---|---|
| S1 | Chat responsiveness | First token p50 < 3s, p95 < 8s over 30 turns |
| S2 | Write safety | 100% of write tool calls pause; 0 executions without a yes; executed args byte-identical to the card |
| S3 | Permission parity | 0 leaks in 20 adversarial prompts from a user without access; chat shows exactly what the app shows |
| S4 | Model independence | Same agent passes its eval set on 2 providers by changing one field |
| S5 | Scheduling | Fires within 90s of due; 0 double fires over 7 days |
| S6 | Cost truth | Recorded cost within 5% of the Gateway's log (exact with `generation_id`) |
| S7 | Budget guard | A run stops at its cap; daily overshoot at most one run |
| S8 | User-made agents | Template to first answer in under 2 minutes, no engineer involved |
| S9 | Approval survives deploy | A pending approval made before a redeploy executes after it |
| S10 | Clean and secure | 0 advisor security warnings; secret scan clean on full history; no secret in any browser bundle |

## Real-run scenarios (M6)

| # | Scenario | Proves |
|---|---|---|
| R1 | Sign in, open Agents, see starters with live meta lines | - |
| R2 | Create an agent from a template, add a write tool, ask it something | S1, S8 |
| R3 | 30 turns across 3 agents | S1 |
| R4 | "Remember I prefer weekly summaries"; new chat: "what do I prefer?" | memory |
| R5 | Ask for a write; approve; diff the target record against the card | S2 |
| R6 | Five writes; decline all; confirm nothing changed | S2 |
| R7 | Hourly routine for 7 days | S5 |
| R8 | Second account opens a private agent by URL | S3 |
| R9 | Swap Anthropic to OpenAI; rerun 10 eval prompts | S4 |
| R10 | Compare a day's Gateway log to `agent_runs` | S6 |
| R11 | $0.05 run cap on a long task | S7 |
| R12 | Leave an action pending, redeploy, approve | S9 |

## Host app adoption (M7)

1. Add the kit's migrations; implement `agent_kit.can_see_team()` with the app's own membership check, so agent RLS matches dashboard RLS.
2. Mount the routes from `api/agents/[...path].ts`.
3. `getToolToken`: forward the user's Supabase access token if the app's MCP verifies Supabase JWTs (most do via JWKS). Scheduled runs need a server-side token for the agent owner.
4. Put "Agents" under the app's Chat nav, behind a feature flag and admin role first. Theme through the app's CSS tokens.
5. Gateway BYOK with the company's provider keys; only `trainsOnData: false` models.
6. Rebuild one existing automation as the first built-in agent; run both for a cycle and compare.

| # | Scenario | Proves |
|---|---|---|
| A1 | Tab hidden with the flag off | - |
| A2 | Ask a metric question; numbers match the dashboard | S1 |
| A3 | Ask for a ticket; nothing filed until approved; ticket matches the card | S2 |
| A4 | User without a restricted team: 20 adversarial prompts | S3 |
| A5 | Builder shows a non-admin only the tools they hold | S3 |
| A6 | Browser bundle contains no gateway key, service key or signing key | S10 |

## Engineer notes

- Create migrations with `supabase migration new <name>`. Unset any stray `SUPABASE_*` env vars before running the CLI so it can't hit the wrong project.
- Pin exact versions. As of 2026-10-06: `ai@7.0.128`, `@ai-sdk/mcp@2.0.67`, `@ai-sdk/react@4.0.131`, `@modelcontextprotocol/sdk@1.32.1`, `@supabase/supabase-js@2.117.2`, `vite@8.3.3`, `react@19.3.0`, `vitest@5.0.3`, `@playwright/test@1.63.0`.
- Use `toolApproval`, not the deprecated `needsApproval`.
- Read MCP annotations from `client.listTools()`; they are not on the AI SDK tool objects.
- Relative imports need `.js` extensions under ESM, or Vercel functions fail at runtime.
- Cron targets the production domain; preview URLs sit behind deployment protection.

## Deferred to v0.2

Lead agent with `send_to_agent` · Workflow SDK for runs over 800s · event triggers · pgvector memory · coding sandboxes · background passes. Add each when real usage shows it's needed.

## References

- AI SDK: [agents](https://ai-sdk.dev/docs/agents/overview) · [tools and approval](https://ai-sdk.dev/docs/ai-sdk-core/tools-and-tool-calling) · [MCP client](https://ai-sdk.dev/docs/ai-sdk-core/mcp-tools)
- Vercel: [AI Gateway](https://vercel.com/docs/ai-gateway) · [model fallbacks](https://vercel.com/docs/ai-gateway/models-and-providers/model-fallbacks) · [function limits](https://vercel.com/docs/functions/limitations) · [Workflow SDK](https://workflow-sdk.dev/docs/ai) · [eve](https://vercel.com/changelog/introducing-eve-an-open-source-agent-framework)
- Supabase: [Cron + pg_net + Vault](https://supabase.com/docs/guides/functions/schedule-functions) · [JWTs and JWKS](https://supabase.com/docs/guides/auth/jwts) · [Data API exposure](https://supabase.com/docs/guides/database/data-api) · [security](https://supabase.com/docs/guides/security/product-security)
- MCP: [2026-07-28 specification](https://blog.mcpservers.org/posts/mcp-spec-2026-07-28)
