-- Run once in the Supabase SQL editor.
create table if not exists orders (
  id                     uuid primary key default gen_random_uuid(),
  course_id              text not null,
  email                  text not null,
  amount_cents           integer not null check (amount_cents > 0),
  currency               text not null default 'EGP',
  status                 text not null default 'pending'
                         check (status in ('pending', 'paid', 'failed')),
  paymob_order_id        text,
  paymob_transaction_id  text,
  created_at             timestamptz not null default now(),
  paid_at                timestamptz
);

-- The browser never talks to this table directly. Only the server
-- (service role key) reads and writes it, so RLS is enabled with no public policies.
alter table orders enable row level security;
