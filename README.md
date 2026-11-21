# LearnSphere

Multi-tenant educational SaaS platform. Arabic-first with full RTL, English supported.

## Status

| Phase | Scope | State |
|---|---|---|
| 1 | Architecture, config, folder structure | Written, not yet installed or run |
| 2 | Design system, responsive UI | Tokens and base components only |
| 3 | Database schema and auth | Schema written with RLS. Auth not yet built |
| 4 to 10 | Tenancy flows, dashboards, course builder, exams, payments, admin, hardening | Not started |

Nothing in this repository has been installed, compiled or tested yet.

## Requirements

- Node.js 20 or newer
- PostgreSQL 15 or newer (or Supabase)

## Setup

```bash
npm install
cp .env.example .env.local     # then fill in real values
npm run db:migrate             # applies db/migrations/*.sql
npm run dev
```

## Structure

```
db/migrations/        SQL schema, ordered, with RLS policies
scripts/              Operational scripts (migrations)
src/app/              Next.js routes (public site, auth, dashboards, API)
src/lib/db/           Server-only database access
src/lib/tenancy/      Tenant context bound to Postgres for RLS
src/lib/payments/     Provider adapter contract; status changes only via verified webhooks
src/lib/i18n/         Locales and dictionaries (ar, en)
```

## Security notes

- The app must connect as a non-superuser role. Superusers bypass RLS.
- Tenant identity comes only from a verified server-side session.
- Payments are marked successful only by verified provider webhooks.
- Secrets live in environment variables. Only `NEXT_PUBLIC_*` values reach the browser.

## Required external accounts (not yet configured)

Stripe, Paymob, Zoom, SMTP, S3 or Supabase Storage, WhatsApp Business API. Each variable is listed in `.env.example`.
