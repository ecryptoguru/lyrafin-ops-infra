# Lyra Ops Plan

Last updated: 2026-06-22 (v2 — final, reviewed and amended)

This is the source-of-truth operating plan for Lyrafin AI's email, social, document-conversion, growth, and automation stack. It supersedes the earlier Contabo/Postiz/listmonk/MarkItDown planning notes and corrects them around the canonical `lyrafinai.com` domain, the full listmonk + SES email migration, Postiz runtime dependencies, and deeper Lyrafin app integrations.

Repository code, current production configuration, and live provider dashboards remain the final runtime authority. If this document conflicts with implemented code, Cloudflare, AWS, Azure, SES, Postiz, listmonk, or payment/provider dashboards, verify the live source before acting.

---

## Final Architecture

Lyra Ops is a separate operating layer that supports the main Lyrafin product without merging third-party app source into `multiasset-ai`.

```txt
Contabo VPS
├── listmonk
├── Postiz
├── PostgreSQL (app DB)
├── PostgreSQL (Temporal DB — separate instance)
├── Redis
├── Temporal + Elasticsearch (for Temporal visibility)
├── Caddy
└── Backups and monitoring

Azure
└── MarkItDown API (Azure Container Apps)
    ├── Fast conversion mode
    └── OCR/table mode with Azure Document Intelligence

Lyrafin app
├── EmailService    -> listmonk / Amazon SES
├── SocialService   -> Postiz (LinkedIn, Facebook/Instagram, YouTube)
│                  -> Hyperagent X/Twitter connector (free X/Twitter path)
└── DocumentService -> MarkItDown / Azure Document Intelligence

Hyperagent Marketing Agent
├── Postiz MCP      -> https://social.lyrafinai.com/mcp with Bearer auth
└── listmonk Skill  -> https://newsletter.lyrafinai.com/api/...
```

The guiding rule is simple: infrastructure tools stay outside the main app, while the main app owns the user-facing contracts, permissions, privacy behavior, credits, rewards, and product workflows.

---

## Repository Strategy

Create a separate infrastructure repo or project named `lyrafin-ops-infra`.

Recommended local path:

```txt
/Users/defiankit/Desktop/lyrafin-ops-infra
```

Do not merge the Postiz or listmonk source code into `multiasset-ai`. The ops repo should hold Docker Compose files, Caddy config, environment templates, backup scripts, restore scripts, monitoring notes, and runbooks. The main app should only integrate through stable internal service clients.

Optional future forks are allowed only for real product changes that cannot be configured cleanly upstream:

- `lyrafin-postiz-fork`
- `lyrafin-listmonk-fork`

The main app should own integration contracts such as `sendEmail`, `schedulePost`, and `convertDocument`. It should not know Postiz/listmonk container internals, Temporal deployment details, or Caddy routing implementation.

---

## Secrets Management

Use **Doppler** as the primary secrets vault across all environments (local, Contabo, Azure, AWS).

Doppler is the preferred secrets manager for this stack. Its developer/free tier is expected to be enough for initial local and solo operation, but plan limits and pricing must be checked before production rollout. Doppler injects secrets directly to Docker Compose at runtime via the Doppler CLI:

```bash
doppler run -- docker compose up -d
```

Project structure in Doppler:

```txt
lyrafin-ops
├── dev        (local development secrets)
├── staging    (if applicable)
└── production (Contabo + Azure production secrets)

lyrafin-app
├── dev
└── production
```

Never store real secrets in `.env` files committed to git. Commit only `.env.example` with placeholder values. Doppler injects real values at runtime via CLI or GitHub Actions integration.

Store Contabo SSH access details, Doppler service tokens, and provider OAuth app credentials as a separate encrypted document in a password manager (1Password or Bitwarden) as a recovery path independent of Doppler.

---

## Local Build And Rehearsal

Build and test the ops stack locally before touching Contabo. The local project should be a sibling of `multiasset-ai`, not a subfolder inside it:

```txt
/Users/defiankit/Desktop/multiasset-ai
/Users/defiankit/Desktop/lyrafin-ops-infra
```

The local ops project should mirror the production deployment shape closely enough to rehearse startup, upgrades, volumes, backups, restore drills, service URLs, and app integrations.

Local project contents:

```txt
lyrafin-ops-infra
├── docker-compose.yml
├── docker-compose.override.yml
├── .env.example
├── caddy/
│   └── Caddyfile
├── listmonk/
│   ├── config.toml
│   └── README.md
├── postiz/
│   └── README.md
├── markitdown-api/
│   ├── Dockerfile
│   ├── app/
│   └── tests/
├── scripts/
│   ├── backup-postgres.sh
│   ├── restore-postgres.sh
│   ├── smoke-local.sh
│   └── doctor.sh
└── runbooks/
    ├── local-setup.md
    ├── contabo-bootstrap.md
    ├── backup-restore.md
    ├── deploy.md
    └── incident-response.md
```

Use Docker Compose profiles so each part can be started independently:

```bash
docker compose --profile email up -d
docker compose --profile social up -d
docker compose --profile convert up -d
docker compose --profile all up -d
```

### Local Service Shape

**email profile:**
```txt
├── listmonk
├── listmonk-postgres
└── mailpit
```

**social profile:**
```txt
├── postiz (app)
├── postiz-postgres
├── postiz-redis
├── temporal
├── temporal-postgres   ← separate Postgres instance required by Temporal
├── temporal-elasticsearch  ← Elasticsearch 7.17 required for Temporal visibility
├── temporal-ui (optional)
└── postiz-uploads (volume)
```

Note: Temporal requires its own PostgreSQL instance and Elasticsearch separately from the Postiz app database. The social profile needs approximately 3–4 GB RAM in local development. Ensure the dev machine has at least 8 GB free before starting the social profile.

**convert profile:**
```txt
└── lyrafin-markitdown-api
```

Local URLs:

```txt
http://localhost:9001 -> listmonk
http://localhost:8025 -> Mailpit
http://localhost:5000 -> Postiz
http://localhost:9100 -> MarkItDown API
```

Local `multiasset-ai` integration env examples:

```env
LISTMONK_BASE_URL=http://localhost:9001
LISTMONK_API_USER=local
LISTMONK_API_TOKEN=local-dev-token
LISTMONK_BLOG_LIST_ID=1
LISTMONK_TRANSACTIONAL_TEMPLATE_ID=1

POSTIZ_BASE_URL=http://localhost:5000
POSTIZ_API_TOKEN=local-dev-token

MARKITDOWN_BASE_URL=http://localhost:9100
MARKITDOWN_API_KEY=local-dev-token
```

Local development rules:

- Keep real production secrets out of local `.env` files; use Doppler CLI or `.env.example` with placeholder values.
- Commit `.env.example`, not `.env`.
- Use Mailpit locally instead of SES.
- Use local-only Postiz provider credentials until real social provider apps are configured.
- Keep Postiz user autoposting disabled in local and production v1.
- Keep MarkItDown URL conversion disabled in local and production v1.
- Run `multiasset-ai` against local ops services only after each individual service passes its own smoke test.
- Treat local Docker volume persistence, backup, and restore as required features, not afterthoughts.

Local build order:

1. Create `lyrafin-ops-infra`.
2. Add Compose profiles and `.env.example`.
3. Start listmonk with Mailpit and verify login plus a test email.
4. Start Postiz with Postgres, Redis, Temporal (+ temporal-postgres + temporal-elasticsearch), and uploads volume.
5. Verify Postiz admin login, registration policy, Temporal connectivity, and upload persistence.
6. Build `lyrafin-markitdown-api`.
7. Verify `GET /health`, DOCX, XLSX, text PDF, scanned PDF, oversized file rejection, unsupported MIME rejection, and timeout behavior.
8. Add backup and restore scripts for local databases and upload volumes.
9. Run restore drills into a clean local Docker environment.
10. Point `multiasset-ai` local env to the local services.
11. Test one integration flow each: newsletter subscribe, social draft/schedule, document conversion, portfolio PDF import, share/reward telemetry.
12. Only after local rehearsal is green, provision and harden Contabo.

---

## Domains

Use the canonical Lyrafin AI domain:

```txt
newsletter.lyrafinai.com -> listmonk
social.lyrafinai.com     -> Postiz
convert.lyrafinai.com    -> MarkItDown API
```

Treat `lyfinai.com` as a typo. Do not purchase it — brand confusion risk. Do not use it.

Benefits of using `lyrafinai.com`:

- Brand trust: users, social platforms, and email recipients see the real Lyrafin AI domain.
- SES deliverability alignment: DKIM, SPF, DMARC, and custom MAIL FROM are cleaner under the canonical domain.
- Simpler DNS and OAuth callback management: social provider apps can point at `social.lyrafinai.com`.
- Consistency with the current app, marketing site, auth, CORS, CSRF, SEO, support docs, and production domain model.
- Enterprise trust: `convert.lyrafinai.com` reads as a private Lyrafin document intelligence service, not a random utility host.

---

## Contabo Deployment

Recommended minimum VPS:

```txt
4 vCPU
8 GB RAM
150 GB SSD
Ubuntu 24.04 LTS
```

This matches the Contabo Cloud VPS 10 storage choice. Because Postiz now brings Redis, Temporal, Temporal Postgres, and Elasticsearch into the local/production shape, treat `8 GB RAM` as the v1 minimum and `16 GB RAM` as the preferred upgrade if Elasticsearch/Temporal memory pressure appears during local rehearsal or early production monitoring.

Install Docker Engine from Docker's official Ubuntu repository. Use Caddy for reverse proxying and automatic HTTPS.

Security baseline:

- Open only ports `22`, `80`, and `443`.
- Use SSH key login only.
- Disable password login for SSH.
- Enable UFW.
- Enable Fail2ban.
- Enable unattended security upgrades.
- Configure Docker log rotation.
- Do not expose Postgres, Redis, or Temporal publicly.
- Keep all application secrets out of git.
- Use Doppler CLI to inject secrets at runtime — never write production secrets to `.env` files on the VPS.

Operational baseline:

- Daily PostgreSQL dumps (both postiz-postgres and temporal-postgres).
- Weekly full backups.
- Back up listmonk uploads/media.
- Back up Postiz uploads/media.
- Back up Postiz Temporal state as required by the deployed stack.
- Store encrypted offsite backups in AWS S3 (preferred — already in use for the main app) or Cloudflare R2.
- Run restore drills before treating the stack as production-ready.
- Alert at 70 percent disk usage and again at 85 percent (via a daily cron health check script — see `scripts/doctor.sh`).

### Media / Upload Storage

Use local VPS storage (Docker named volume) for v1. The 150 GB SSD has adequate capacity for early-stage post media volumes, Docker images, database dumps, restore staging, logs, and operating-system headroom.

Migrate to external object storage when either condition is met:
- Upload volume exceeds 20 GB, or
- A VPS migration or disk expansion is planned (external storage avoids re-pointing existing upload URLs)

When migrating, preferred options in order:
1. **Cloudflare R2** — no egress fees, free tier (10 GB + 1M ops/month), S3-compatible. Best fit for Postiz media.
2. **AWS S3** — already in use for the main app; consolidates billing. Egress fees apply (~$0.09/GB).
3. **Azure Blob Storage** — acceptable if Azure is preferred; similar pricing to S3.

Keep `STORAGE_PROVIDER=local` for both local development and production v1. When migrating to external storage, update `STORAGE_PROVIDER` and the corresponding provider env vars in Doppler.

### Deployment Process

Document the deployment runbook in `runbooks/deploy.md`. For v1:

```bash
# On Contabo VPS — update services to latest versions
git pull
doppler run -- docker compose pull
doppler run -- docker compose up -d
docker compose ps   # verify all services healthy
```

No automated CI/CD is required for v1. Add GitHub Actions + SSH deployment in a later iteration when deployment cadence increases.

### Known Limitations (v1)

Single-VPS deployment is accepted for v1. Estimated RTO from backup: approximately 2 hours. This architecture will be re-evaluated at 500+ active users or the first SLA commitment to a B2B customer. The single-VPS risk is a documented and accepted trade-off for the bootstrapped phase.

### Monitoring

Add **Uptime Robot** (free tier, 50 monitors at 5-minute intervals) monitoring:
- `https://newsletter.lyrafinai.com/health`
- `https://social.lyrafinai.com/health`
- `https://convert.lyrafinai.com/health`
- Main Lyrafin app URL

Configure email alerts to `ankit@lyrafinai.com` for any downtime event. Setup time: approximately 30 minutes.

---

## Email Strategy — listmonk + SES (Full Cutover)

listmonk handles **all email** — transactional and campaigns — from deployment. Brevo is deprecated entirely. There is no hybrid phase.

| Email type | Provider |
|---|---|
| Auth verification | listmonk + SES |
| Welcome email | listmonk + SES |
| Password reset | listmonk + SES |
| Onboarding sequence | listmonk + SES |
| Reengagement | listmonk + SES |
| Contact form | listmonk + SES |
| AMI webhook emails | listmonk + SES |
| Newsletter campaigns | listmonk + SES |
| Blog digest | listmonk + SES |
| Lifecycle campaigns | listmonk + SES |

### SES Production Access — Critical Path

AWS SES starts in sandbox mode. **Submit the SES production access request immediately — at the same time as local rehearsal begins, not at deployment time.** Approval typically takes 24–72 hours. By the time Contabo is provisioned and listmonk is deployed, SES should already be out of sandbox.

Do not cut over the app from Brevo to listmonk until SES production access is confirmed. Once confirmed, migrate all email flows to listmonk + SES at Step 16, remove Brevo from the app, and cancel the Brevo account within 14 days.

### Brevo Deprecation

- Remove all Brevo configuration from `src/lib/email/brevo.ts` at Step 16.
- Cancel Brevo subscription once all email flows are confirmed working through listmonk + SES.
- 14-day cancellation window as a rollback buffer, then close the account fully.

### listmonk Plan

Use Amazon SES SMTP for sending.

Configure SES:

- Verified sending identity for `lyrafinai.com` or a dedicated mail subdomain.
- DKIM.
- SPF.
- DMARC.
- Custom MAIL FROM.
- SES production access (request immediately — starts the approval clock).
- SES SMTP credentials.
- Encrypted SMTP connection.
- Bounce and complaint handling.

Bounce webhook:

```txt
https://newsletter.lyrafinai.com/webhooks/service/ses
```

Use listmonk for:

- Newsletter campaigns.
- Blog digest emails.
- Lifecycle emails.
- Transactional emails through generic templates.
- Agent-assisted campaign drafts.
- Subscriber and segment management.
- Campaign analytics for growth review.

Initial list design:

- `blog_subscribers`
- `product_updates`
- `trial_onboarding`
- `reengagement`
- `creator_referrals`
- `internal_test`

All first sends must go to `internal_test` before a public list.

---

## Email Integration In Main App

Replace `src/lib/email/brevo.ts` with a provider-neutral listmonk email layer. Brevo must not remain in the steady-state architecture; it is only a temporary rollback provider until SES production access and all listmonk email flows are verified.

New environment variables:

```env
LISTMONK_BASE_URL=https://newsletter.lyrafinai.com
LISTMONK_API_USER=<api-user>
LISTMONK_API_TOKEN=<api-token>
LISTMONK_BLOG_LIST_ID=<blog-list-id>
LISTMONK_TRANSACTIONAL_TEMPLATE_ID=<transactional-template-id>
EMAIL_FROM_ADDRESS=admin@lyrafinai.com
EMAIL_FROM_NAME=Lyrafin AI
```

Current Brevo call sites that need migration to listmonk + SES at Step 16:

- Auth verification email.
- Welcome email.
- Onboarding emails.
- Reengagement emails.
- Contact form email.
- Blog digest email.
- AMI webhook emails.
- Newsletter subscribe route.
- Blog/newsletter preferences route.

Implementation shape:

- Keep the existing app-rendered HTML and text templates at first.
- Use one generic listmonk transactional template that accepts app-rendered `subject`, `html`, `text`, and recipient data.
- Preserve existing error behavior: email provider failure should not crash unrelated product flows unless the email is required for security.
- Keep idempotency and retry behavior around webhook-triggered sends.
- Update tests that currently mock Brevo to mock the provider-neutral listmonk email layer instead.
- Update privacy policy, product docs, `CODEBASE.md`, and environment templates from Brevo to listmonk + SES once the migration is complete.

---

## Postiz Plan

Use the official Postiz Docker Compose shape and pin versions. Postiz should initially support Lyrafin-owned/team publishing, not uncontrolled user autoposting.

Required services:

- Postiz app.
- postiz-postgres.
- postiz-redis.
- Temporal.
- temporal-postgres (separate Postgres instance for Temporal).
- temporal-elasticsearch (Elasticsearch 7.17 for Temporal visibility).
- Uploads volume.

Configuration requirements:

- Disable public registration (`DISABLE_REGISTRATION=true` after first signup).
- Restrict admin access.
- Use strong secrets for JWT/session configuration (generated via Doppler).
- Set external URL to `https://social.lyrafinai.com`.
- Keep internal backend/service URLs on the Docker network.
- Store uploads on a persistent local Docker named volume for v1. Migrate to Cloudflare R2 or AWS S3 when local volume exceeds 20 GB or before any VPS migration.
- Set `IS_GENERAL=true` for self-hosted routing.
- Set `DISALLOW_PLUS=true` to hide cloud billing UI.

### Social Provider Priority

**First priority (register OAuth apps at Step 10, before Postiz deployment):**

- LinkedIn — `w_member_social` permission, OAuth callback: `https://social.lyrafinai.com/connect/linkedin/callback`. Registration takes 30 minutes; LinkedIn review approval takes 1–3 days. Start at Step 10, not at deployment.
- Facebook/Instagram — Meta Developer account, app review required. Timeline: days to weeks. Start registration at Step 10.

**Secondary (add when a real publishing workflow exists):**

- YouTube.

**Not via Postiz — use Hyperagent native connector:**

- X/Twitter. X/Twitter posts are handled through Hyperagent's native free X/Twitter connector. Do not configure Twitter in Postiz for v1. Keep X/Twitter approval and posting inside Hyperagent; keep LinkedIn, Facebook/Instagram, and YouTube workflows inside Postiz.

Do not connect every provider on day one. Add providers only when Lyrafin has a real publishing workflow for them.

---

## Hyperagent Integration

Hyperagent (the Lyrafin AI Marketing Agent) connects to the Contabo-hosted services over standard HTTPS. No VPN or private networking is required — Caddy on Contabo handles TLS termination and the services are reachable at their public subdomains.

### Postiz — MCP Server Connection

Postiz exposes a native MCP (Model Context Protocol) server. Register it once in Hyperagent's integrations panel and the marketing agent can schedule posts, list connected accounts, generate images, and pull analytics conversationally.

MCP server URL:

```txt
URL: https://social.lyrafinai.com/mcp
Header: Authorization: Bearer {POSTIZ_API_KEY}
```

Transport: Streamable HTTP.

Get the API key from: Postiz Settings → Developers → Public API.

Do not use the API-key-in-URL variant in Lyrafin docs or runbooks. Bearer auth keeps the key out of URLs, browser history, reverse-proxy access logs, and copied screenshots.

Available MCP tools:

| Tool | Purpose |
|---|---|
| `integrationList` | List connected social accounts + IDs |
| `integrationSchema` | Get platform-specific posting rules and character limits |
| `schedulePostTool` | Create, schedule, draft, or publish posts |
| `generateImageTool` | Generate an AI image for post attachment |
| `generateVideoTool` | Generate AI video for post attachment |
| `groupList` | List customer groups |
| `triggerTool` | Platform-specific helpers (list Discord channels, Reddit subreddits) |

### listmonk — Hyperagent API Skill

listmonk has no MCP server. Build a Hyperagent API skill using the listmonk REST API with API user + token stored as a Hyperagent credential.

Base URL: `https://newsletter.lyrafinai.com`
Auth: Basic auth with `LISTMONK_API_USER` and `LISTMONK_API_TOKEN`

Key endpoints:

| Action | Endpoint |
|---|---|
| Create campaign (draft) | `POST /api/campaigns` |
| Send campaign | `PUT /api/campaigns/{id}/status` (body: `{"status":"running"}`) |
| Add subscriber | `POST /api/subscribers` |
| Send transactional | `POST /api/tx` |
| Get running campaign stats | `GET /api/campaigns/running/stats?campaign_id={id}` |
| Get campaign analytics | `GET /api/campaigns/analytics/{type}` |
| List subscribers | `GET /api/subscribers` |

### Workflows Enabled

| Workflow | Execution path |
|---|---|
| Schedule LinkedIn post | Ankit approves → agent calls `schedulePostTool` via Postiz MCP → published at scheduled time |
| Post to X/Twitter | Ankit approves → agent calls Hyperagent native X/Twitter connector directly |
| Send newsletter campaign | Agent drafts HTML → Ankit approves → agent calls listmonk API skill → Ankit reviews in listmonk UI → sends |
| RSS blog → social auto-post | Configured in Postiz UI → Postiz auto-drafts → Ankit approves in calendar |
| Weekly analytics report | Agent calls Postiz analytics API + listmonk stats API → formats summary in chat |
| Content calendar | Agent drafts month's posts → Ankit approves → agent schedules all via Postiz MCP |

### Security Notes

- Postiz and listmonk API keys are stored in Hyperagent's credential system — never in plaintext in the conversation or files.
- Caddy on Contabo serves all endpoints over HTTPS only. HTTP redirects to HTTPS.
- Use the Bearer token MCP variant to keep the API key out of Caddy access logs.
- Keep API-call volume conservative and monitor provider/API errors during local and staging rehearsal. Do not hard-code Postiz or provider rate limits into the architecture; verify the current limits from Postiz and connected social-provider dashboards before scheduling large batches.

---

## Social And Rewards Integration

Build `SocialService` inside the Lyrafin app as the app-side boundary around Postiz. This service should support scheduling approved content, reading publish state, and attaching campaign metadata.

Use Postiz for:

- Founder/team content scheduling.
- Campaign calendars.
- Approved post queues.
- Social performance workflow.
- Draft review and approval.
- Repurposing Lyrafin-approved content into platform-specific post formats.

Use existing app systems for user rewards:

- Share cards.
- Referral links.
- Credit transactions.
- XP/rewards.
- Share telemetry.

Reward design:

- Reward small verified share actions with capped XP, not immediate credits.
- Larger credit rewards should require referral signup, referral activation, XP redemption, or an admin-approved campaign.
- Rewards must be idempotent.
- Avoid incentives that encourage spam.
- Never auto-post from a user account without explicit review and consent.
- Do not reward sensitive/private portfolio content being posted publicly.
- Do not treat X, LinkedIn, or Reddit popup launches as verified shares.
- Keep popup/open telemetry separate from copy, download, native share completion, referral signup, referral activation, and paid conversion.

Share-card and telemetry rules:

- Share copy must be finance-appropriate, accurate, and privacy-safe.
- Use valid platform hashtags such as `#LyrafinAI`, not strings with spaces.
- LinkedIn sharing should rely on the URL and Open Graph card; custom LinkedIn captions should be copied by the user.
- Portfolio share cards should expose public-safe risk or health takeaways, not holdings, balances, uploaded documents, or private account details.
- Authenticated share events should be written to durable app telemetry as well as Redis aggregates.
- Redis share aggregates are best-effort; Redis failure must not block durable telemetry or eligible XP attribution.
- Durable share telemetry should store only safe metadata: user, action, kind, mode, path, target, campaign, rewarded XP, rewarded credits, and timestamp.
- Generic share rewards should use `share_analysis` XP with a daily cap.
- Direct credit grants must use `CreditTransaction.referenceId` idempotency when campaign credits are introduced.

### XP Daily Cap Implementation

The `share_analysis` XP daily cap (5 XP per verified action, capped at 3 per day = 15 XP/day maximum) must be enforced through the app's durable XP/share-event data model, not Redis alone.

Implementation: use the current durable share/XP records where possible, and introduce a new daily-activity model only if the existing schema cannot express `(userId, actionType, date)` idempotency cleanly. Redis aggregate is best-effort and for performance only. The database record is authoritative for cap enforcement. This prevents cap bypass on Redis failure and satisfies idempotency requirements for the high-risk credits/rewards zone.

Suggested product loop:

```txt
User generates portfolio, asset, compare, or stress-test insight
-> Lyra creates a private-safe share card
-> user shares, copies, downloads, or attaches referral link
-> app records share event
-> app grants capped XP for verified copy/download/native share actions
-> referral signup/activation grants larger credits or discounts
```

Reward examples:

- 0 XP for opening the share sheet; this is telemetry only.
- 0 XP for X, LinkedIn, or Reddit popup launch; this is intent telemetry only.
- 5 XP for verified copy/download/native share completion, capped at 3 per day through `share_analysis`.
- 50 credits for a referee signup.
- 75 credits for an activated referral.
- Larger tier bonuses through the existing referral tier model.
- Future campaign credits only after explicit anti-abuse and idempotency rules are in place.

---

## MarkItDown / Document Intelligence Plan

Build a separate service named `lyrafin-markitdown-api`.

Deploy it on Azure Container Apps as a private backend service for Lyrafin. It should not be marketed as a public converter in v1.

Endpoints:

```txt
GET  /health
POST /v1/convert/file
POST /v1/convert/blob
```

Do not ship public `POST /v1/convert/url` in v1. URL conversion creates SSRF and abuse risk. Add it later only with strict allowlisting or controlled server-side fetch rules.

Fast mode:

- DOCX.
- PPTX.
- XLSX.
- CSV.
- HTML.
- JSON.
- Text PDFs.

OCR/table mode with Azure Document Intelligence:

- Scanned PDFs.
- Broker statements.
- Screenshots.
- Forms.
- Invoices.
- Table-heavy documents.

Security requirements:

- Server-to-server API key or JWT.
- MIME allowlist.
- Max file size.
- Max page count.
- Conversion timeout.
- Temporary file cleanup.
- No document content in logs.
- Block private IP URL fetching.
- Optional malware scanning later.
- Per-user and per-environment rate limits.
- Budget alerts for Azure Container Apps and Document Intelligence usage.

Recommended launch posture:

- Azure Container Apps Consumption plan.
- Minimum replicas: `1` (not 0 — cold starts of 5–15 seconds are unacceptable for user-facing portfolio import flows).
- Maximum replicas: `3`.
- External ingress only if protected by API auth and network controls.
- Store secrets in Container Apps secrets or Azure Key Vault. Document recovery path in Doppler.
- Use production Document Intelligence tier for real workloads; do not depend on free-tier capacity for product behavior.

---

## Document And Portfolio Integration

MarkItDown should replace or improve the extraction path behind the existing document upload. It should not create a competing user-facing document system.

Preserve current app ownership:

- `UserDocument`.
- User ownership checks.
- Private Lyra Mode behavior.
- Prompt-injection guardrails.
- Plan and credit rules.
- Existing Lyra context boundaries.

Store normalized extracted markdown/text back into the current document model. The app should continue to decide what text is inserted into Lyra context and how much is allowed.

Add metadata later:

- Extraction mode.
- Page count.
- Parser confidence.
- Detected tickers.
- Detected tables.
- Detected holdings.
- Source file hash.
- Conversion duration.

Use the same conversion service for portfolio PDF import. Broker PDFs and statements should be converted into structured holdings candidates before any write to `PortfolioHolding`.

Portfolio import flow:

```txt
User uploads broker PDF/statement
-> DocumentService converts it
-> app extracts holdings candidates
-> user reviews symbols, quantities, prices, and currency
-> app writes approved holdings to PortfolioHolding
-> portfolio health and Lyra context update
```

Do not auto-write portfolio holdings from raw OCR output without a review step.

---

## Growth And Product Ideas

High-value ideas to build on top of this stack:

- Monthly portfolio health digest through listmonk.
- Weekly market intelligence newsletter generated from approved Lyrafin facts.
- Lead nurturing sequences for subscribers who have not signed up.
- Trial onboarding sequence tied to actual activation events.
- Creator/referral campaigns with tracked links.
- Research library for converted PDFs, saved Lyra answers, reports, and memos.
- Social-ready cards for asset insights, portfolio health, stress tests, comparisons, rewards, and referrals.
- Admin growth dashboard combining listmonk campaigns, Postiz activity, referral stats, share telemetry, and conversion events.
- Agent-assisted content drafting with human approval before sending or posting.
- "Turn this Lyra answer into a post" workflow for founder/team users.
- "Turn this portfolio insight into a private-safe share card" workflow for users.
- "Turn this document into a research memo" workflow for document-aware Lyra.
- Segment newsletters by plan, activation state, watched assets, and document/portfolio usage.

The best product strategy is not to expose these tools as generic utilities. Use them to make Lyrafin's existing strengths more repeatable: document-aware analysis, portfolio intelligence, shareable insights, referral growth, and lifecycle education.

---

## Build Order

1. Create `lyrafin-ops-infra` locally as a sibling of `multiasset-ai`. **Also at this step: submit the AWS SES production access request.** Approval typically takes 24–72 hours — it must be confirmed before the Brevo cutover at Step 16. Submitting now means SES approval runs in parallel with local rehearsal and Contabo setup, not after it.
2. Build local Docker Compose profiles for email, social, convert, and all. Update the social profile to include `temporal-postgres` and `temporal-elasticsearch` (Temporal requires these separately from the app database).
3. Rehearse listmonk locally with Mailpit.
4. Rehearse Postiz locally with its required postiz-postgres, postiz-redis, Temporal, temporal-postgres, temporal-elasticsearch, and uploads volume.
5. Build and test `lyrafin-markitdown-api` locally.
6. Add local backup, restore, doctor, and smoke scripts.
7. Run local restore drills into a clean Docker environment.
8. Point `multiasset-ai` local env to the local ops services.
9. Test newsletter, social, document, portfolio import, share telemetry, XP, and referral flows locally.
10. Configure Cloudflare DNS for the three production subdomains. **Also at this step: register the LinkedIn developer app** (OAuth callback: `https://social.lyrafinai.com/connect/linkedin/callback`). LinkedIn review takes 1–3 days — start now, not at deployment. Begin the Meta developer app registration for Facebook/Instagram.
11. Provision Contabo and harden the server. Install Doppler CLI. Document Contabo SSH access in password manager.
12. Deploy Caddy, Postgres (app + Temporal), Redis, Temporal, and Elasticsearch on Contabo.
13. Deploy listmonk on Contabo. Create Hyperagent listmonk API skill with API token credential.
14. Configure SES SMTP credentials and bounce/complaint webhook. (SES production access was submitted at Step 1 and should be approved by now. If not yet approved, do not proceed to Step 16 — wait for confirmation before cutting over from Brevo.)
15. Test listmonk with internal subscribers only.
16. Migrate all email flows from Brevo to listmonk + SES (only after SES production access is confirmed). Replace `src/lib/email/brevo.ts` with the provider-neutral listmonk layer. Test every email flow: auth verification, welcome, onboarding, reengagement, contact, blog digest, AMI webhooks. Remove all Brevo configuration from the app. Cancel Brevo subscription within 14 days.
17. Deploy Postiz on Contabo. Use local volume storage for v1 (`STORAGE_PROVIDER=local`). Verify uploads persist after container restart before connecting any social providers.
18. Configure first-priority social providers in Postiz once LinkedIn/Meta apps are approved. X/Twitter is handled by Hyperagent's native free X/Twitter connector — do not configure in Postiz.
19. **Register Postiz MCP server in Hyperagent.** URL: `https://social.lyrafinai.com/mcp` with Bearer token. Test: schedule a draft LinkedIn post via Hyperagent conversation. Confirm it appears in the Postiz calendar.
20. Deploy MarkItDown to Azure Container Apps. Set `minReplicas: 1`. Store secrets in Container Apps secrets or Azure Key Vault.
21. Integrate `DocumentService` into upload and portfolio import.
22. Add `SocialService` and share/reward integrations. Implement `share_analysis` XP daily cap through the durable share/XP data model; add a new daily-activity model only if the existing schema is insufficient.
23. Add Uptime Robot monitoring for all three subdomains and the main Lyrafin app.
24. Add production monitoring, backups, and restore drills. Document RTO target: 2 hours from backup.
25. Update docs, privacy policy, env templates, and operational runbooks. Update the Hyperagent Integration section with the confirmed MCP URL and credential storage location, but never paste live API keys into repo docs.

---

## Verification Checklist

Local rehearsal:

- `lyrafin-ops-infra` exists outside `multiasset-ai`.
- `.env.example` exists and contains no real secrets.
- Doppler project configured for `lyrafin-ops/dev` environment.
- Compose profiles start independently: `email`, `social`, `convert`, and `all`.
- `social` profile includes temporal-postgres and temporal-elasticsearch.
- listmonk starts locally.
- Mailpit receives a listmonk test email.
- Postiz starts locally with postiz-postgres, postiz-redis, Temporal, temporal-postgres, temporal-elasticsearch, and uploads.
- Postiz uploads persist after container restart.
- MarkItDown API starts locally.
- MarkItDown local API rejects missing or invalid API auth.
- MarkItDown local API converts DOCX, XLSX, text PDF, and scanned PDF.
- Local backup scripts create restorable dumps.
- Local restore scripts restore into a clean Docker environment.
- `multiasset-ai` can point to local listmonk, Postiz, and MarkItDown URLs without production secrets.
- Browser smoke tests pass for the local integration flows.

Infrastructure:

- DNS resolves for `newsletter.lyrafinai.com`.
- DNS resolves for `social.lyrafinai.com`.
- DNS resolves for `convert.lyrafinai.com`.
- Caddy certificates are issued.
- Only ports `22`, `80`, and `443` are open publicly.
- Postgres, Redis, Temporal, and Elasticsearch are not publicly exposed.
- Docker containers restart cleanly after VPS reboot.
- Doppler CLI is installed and configured on the VPS.
- Uptime Robot monitoring is active for all three subdomains.

Email:

- listmonk login works.
- SES test send passes DKIM, SPF, and DMARC.
- SES production access request submitted.
- Bounce webhook processes a test bounce.
- Complaint webhook path is documented and tested where possible.
- Newsletter subscribe flow works.
- Blog preference subscribe/unsubscribe flow works.
- SES production access is confirmed (out of sandbox) before Step 16 cutover.
- All email flows route through listmonk + SES after Step 16: auth verification, welcome, onboarding, reengagement, contact, blog digest, AMI webhooks, newsletters.
- Brevo configuration fully removed from the app.
- Brevo account cancelled (or within 14-day cancellation window).

Postiz:

- Postiz admin works.
- Public registration is disabled.
- LinkedIn provider connected (after app approval).
- One test post can be scheduled to LinkedIn.
- One test post can be cancelled.
- Uploads persist after container restart (local volume confirmed).
- X/Twitter is NOT configured in Postiz (handled via Hyperagent).

Hyperagent Integration:

- Postiz MCP server registered in Hyperagent.
- `integrationList` MCP tool returns connected LinkedIn account.
- `schedulePostTool` successfully queues a draft LinkedIn post from a Hyperagent conversation.
- listmonk API skill created with API token credential.
- listmonk skill can create a campaign draft via API call.
- Hyperagent native X/Twitter connector tested for posting.

MarkItDown:

- Health endpoint works.
- DOCX conversion works.
- XLSX conversion works.
- Text PDF conversion works.
- Scanned PDF OCR works.
- Oversized files are rejected.
- Unsupported MIME types are rejected.
- Private-IP/URL SSRF path is blocked.
- Timeouts are enforced.
- Logs do not include document content.
- `minReplicas` is set to 1 in Azure Container Apps configuration.

Lyrafin app:

- Lyra document upload still enforces ownership.
- Lyra document upload still enforces prompt-injection guards.
- Private Lyra Mode behavior is preserved.
- Portfolio PDF import produces reviewable holdings before save.
- Share-card copy is platform-valid and privacy-safe.
- X, LinkedIn, and Reddit popup opens are tracked as intent, not verified share success.
- Copy, download, and native share completion can award capped `share_analysis` XP.
- `share_analysis` daily cap enforced through durable DB records (not Redis-only).
- Generic share actions do not grant direct credits.
- Credit reward flow is idempotent.
- Credit reward flow is daily capped.
- Referral copy matches the backend: 50 credits for referee signup, 75 credits after activation.
- Referral activation still grants the larger reward only once.

Backups:

- listmonk database restore succeeds in a clean environment.
- Postiz database restore succeeds in a clean environment.
- Postiz upload restore succeeds in a clean environment.
- Temporal state restore path is documented and tested.
- Environment/secrets recovery path is documented (Doppler + password manager).

---

## Assumptions

- Local rehearsal happens before Contabo production deployment.
- `lyrafin-ops-infra` is a sibling project outside `multiasset-ai`.
- `lyrafinai.com` is the canonical production domain.
- listmonk handles all email (transactional and campaigns) from deployment. Brevo is deprecated entirely at Step 16. SES production access must be confirmed before the Brevo cutover happens.
- Postiz is initially for Lyrafin-owned/team publishing. X/Twitter is handled via Hyperagent's native free connector, not through Postiz.
- User autoposting is not v1.
- MarkItDown is a private backend service, not a public converter product in v1.
- Single-VPS deployment is accepted for v1. Estimated RTO: 2 hours from backup. Will be re-evaluated at 500+ users or first B2B SLA commitment.
- Doppler is the secrets management tool. AWS Secrets Manager is not used for this stack.
- The first implementation step is documentation only; app code changes happen in later focused work.

---

## Current Decision Summary

This is the preferred setup:

- Separate ops repo for deployment and runbooks.
- Canonical `lyrafinai.com` subdomains.
- Contabo for persistent listmonk/Postiz stack.
- Azure Container Apps for stateless MarkItDown conversion (minReplicas: 1).
- SES as the sending layer under listmonk for all email — transactional and campaigns. Brevo deprecated fully at Step 16.
- Doppler for secrets management across all environments.
- Provider-neutral app services in `multiasset-ai`.
- Hyperagent Marketing Agent connected to Postiz via MCP and listmonk via API skill.
- X/Twitter handled via Hyperagent's native free X/Twitter connector.
- Local VPS storage for Postiz uploads in v1. Migrate to Cloudflare R2 or AWS S3 when volume exceeds 20 GB or before a VPS migration.
- Uptime Robot for endpoint monitoring.
- Deep product integrations for documents, portfolio import, share cards, rewards, campaigns, and lifecycle email.

The goal is to build Lyrafin's growth and document operating layer, not merely host three admin tools.
