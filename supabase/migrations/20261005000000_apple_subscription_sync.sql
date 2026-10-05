-- DRAFT -- NOT APPLIED. Review before running.
-- Apple-verified subscription state, fed by the apple-subscription-webhook
-- edge function (App Store Server Notifications V2).

-- 1. Apple's own record of each subscription, keyed by originalTransactionId
--    (the ID that stays the same across every renewal). Written only by the
--    edge function (service role). No client policies = clients cannot read
--    or write it directly.
create table if not exists public.apple_subscription_state (
  original_transaction_id text primary key,
  product_id              text not null,
  expires_at              timestamptz,
  status                  text not null,   -- active | expired | revoked
  environment             text,            -- Sandbox | Production
  last_notification_type  text,
  last_notification_uuid  text,
  updated_at              timestamptz not null default now()
);
alter table public.apple_subscription_state enable row level security;

-- 2. Lets the subscriptions row be matched to Apple's renewal chain.
alter table public.subscriptions
  add column if not exists original_transaction_id text;
create index if not exists subscriptions_original_txn_idx
  on public.subscriptions (original_transaction_id);

-- 3. Called by the app right after it records a purchase. Copies Apple's
--    verified dates onto the signed-in user's own rows when Apple's
--    notification has already arrived (it can beat the app to the database).
create or replace function public.reconcile_my_subscription()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.subscriptions s
     set original_transaction_id = coalesce(s.original_transaction_id, a.original_transaction_id),
         expires_at = a.expires_at,
         status     = a.status,
         updated_at = now()
    from public.apple_subscription_state a
   where s.user_id = auth.uid()
     and s.status <> 'lifetime'
     and (s.original_transaction_id = a.original_transaction_id
          or s.transaction_id = a.original_transaction_id);
end;
$$;
revoke all on function public.reconcile_my_subscription() from public, anon;
grant execute on function public.reconcile_my_subscription() to authenticated;
