-- The Free Vault v4.1.1 — finalizzazione catalogo senza timeout.
-- Eseguire dopo 20260610_v41_catalog_performance.sql.

create index if not exists catalog_items_store_run_listing_idx
on public.catalog_items(store, sync_run_id, listing_id);

create index if not exists catalog_items_store_run_match_idx
on public.catalog_items(store, sync_run_id, match_key);

create or replace function public.cleanup_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
declare
  v_deleted integer := 0;
  v_limit integer := greatest(100, least(coalesce(p_limit, 5000), 10000));
begin
  with doomed as (
    select ci.listing_id
    from public.catalog_items ci
    where ci.store = p_store
      and ci.sync_run_id <> p_run_id
    order by ci.listing_id
    limit v_limit
  )
  delete from public.catalog_items ci
  using doomed d
  where ci.listing_id = d.listing_id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.cleanup_catalog_sync(text, uuid, integer) from public;
grant execute on function public.cleanup_catalog_sync(text, uuid, integer) to service_role;

create or replace function public.finalize_catalog_sync(
  p_store text,
  p_run_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
declare
  v_listing_count bigint;
  v_canonical_count bigint;
begin
  v_listing_count := nullif(p_metadata ->> 'listing_count', '')::bigint;
  v_canonical_count := nullif(p_metadata ->> 'canonical_count', '')::bigint;

  -- Fallback per client vecchi. Il client v4.1.1 passa già entrambi i conteggi.
  if v_listing_count is null or v_canonical_count is null then
    select count(*), count(distinct match_key)
    into v_listing_count, v_canonical_count
    from public.catalog_items
    where store = p_store
      and sync_run_id = p_run_id;
  end if;

  insert into public.catalog_sync_state (
    store, run_id, status, listing_count, canonical_count,
    started_at, completed_at, error_message, metadata, updated_at
  )
  values (
    p_store, p_run_id, 'completed', v_listing_count, v_canonical_count,
    now(), now(), null, coalesce(p_metadata, '{}'::jsonb), now()
  )
  on conflict (store) do update set
    run_id = excluded.run_id,
    status = 'completed',
    listing_count = excluded.listing_count,
    canonical_count = excluded.canonical_count,
    completed_at = now(),
    error_message = null,
    metadata = excluded.metadata,
    updated_at = now();

  return jsonb_build_object(
    'store', p_store,
    'listing_count', v_listing_count,
    'canonical_count', v_canonical_count,
    'completed_at', now()
  );
end;
$$;

revoke all on function public.finalize_catalog_sync(text, uuid, jsonb) from public;
grant execute on function public.finalize_catalog_sync(text, uuid, jsonb) to service_role;
