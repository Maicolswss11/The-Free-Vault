-- The Free Vault v5.0.2
-- Wrapper RPC a singolo parametro JSONB per evitare ambiguità di risoluzione
-- della firma PostgREST sulla funzione batch IGDB a nove argomenti.

begin;

create or replace function public.upsert_igdb_master_payload(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '90s'
as $$
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'p_payload deve essere un oggetto JSON';
  end if;

  return public.upsert_igdb_master_batch(
    nullif(p_payload ->> 'p_run_id', '')::uuid,
    coalesce(nullif(p_payload ->> 'p_cursor_id', '')::bigint, 0),
    coalesce(p_payload -> 'p_games', '[]'::jsonb),
    coalesce(p_payload -> 'p_platforms', '[]'::jsonb),
    coalesce(p_payload -> 'p_releases', '[]'::jsonb),
    coalesce(p_payload -> 'p_external_ids', '[]'::jsonb),
    coalesce(p_payload -> 'p_titles', '[]'::jsonb),
    coalesce(p_payload -> 'p_aliases', '[]'::jsonb),
    coalesce(p_payload -> 'p_projections', '[]'::jsonb)
  );
end;
$$;

revoke all on function public.upsert_igdb_master_payload(jsonb) from public;
grant execute on function public.upsert_igdb_master_payload(jsonb) to service_role;

comment on function public.upsert_igdb_master_payload(jsonb) is
'Wrapper PostgREST stabile per l''upsert batch IGDB; riceve un solo oggetto JSONB e delega alla funzione interna tipizzata.';

commit;

notify pgrst, 'reload schema';
