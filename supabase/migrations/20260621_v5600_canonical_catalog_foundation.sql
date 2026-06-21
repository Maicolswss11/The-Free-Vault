-- Ludograph v5.6.0 — Canonical Catalog Foundation.
--
-- Da questa versione il catalogo pubblico viene trattato come un archivio di
-- opere canoniche: IGDB/master descrive l'identità del gioco, mentre Steam,
-- Epic, PlayStation e altri store restano listing, alias, disponibilità o
-- promozioni collegate alla scheda master. Questa migrazione non elimina record
-- storici: crea il livello di alias/availability e rende le RPC principali
-- capaci di risolvere qualunque chiave legacy verso una scheda canonica.

begin;

create table if not exists public.catalog_game_aliases (
  alias_key text primary key,
  canonical_key text not null references public.catalog_games(match_key) on delete cascade,
  alias_kind text not null default 'legacy'
    check (alias_kind in ('legacy', 'store', 'listing', 'canonical_id', 'master', 'editorial', 'redirect')),
  source text,
  confidence numeric(4,3) not null default 1.000 check (confidence >= 0 and confidence <= 1),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (alias_key <> '')
);

create index if not exists catalog_game_aliases_canonical_key_idx
on public.catalog_game_aliases(canonical_key);

create index if not exists catalog_game_aliases_source_idx
on public.catalog_game_aliases(source);

create table if not exists public.game_store_listings (
  id bigserial primary key,
  canonical_key text not null references public.catalog_games(match_key) on delete cascade,
  store text not null,
  listing_id text not null,
  external_id text,
  namespace text,
  title text,
  store_url text,
  image_url text,
  platform_family text,
  original_price bigint,
  discount_price bigint,
  currency_code text,
  offer_type text,
  category_group text,
  metadata jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique(store, listing_id)
);

create index if not exists game_store_listings_canonical_key_idx
on public.game_store_listings(canonical_key);

create index if not exists game_store_listings_store_idx
on public.game_store_listings(store);

create index if not exists game_store_listings_external_idx
on public.game_store_listings(store, external_id);

create or replace function public.touch_catalog_game_aliases_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists catalog_game_aliases_touch_updated_at on public.catalog_game_aliases;
create trigger catalog_game_aliases_touch_updated_at
before update on public.catalog_game_aliases
for each row execute function public.touch_catalog_game_aliases_updated_at();

create or replace function public.catalog_is_master_catalog_game(p_game public.catalog_games)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    (p_game).source_kind = 'master'
    or (p_game).offer_type = 'IGDB_MASTER'
    or (p_game).match_key like 'master:igdb:%'
    or coalesce((p_game).categories, '{}'::text[]) @> array['master']::text[],
    false
  );
$$;

create or replace function public.catalog_work_key_for_game(p_game public.catalog_games)
returns text
language sql
stable
security definer
set search_path = ''
as $$
with typed as (
  select
    coalesce(g.game_type, 'unknown') as game_type,
    public.catalog_editorial_base_title((p_game).title) as title_key,
    coalesce((p_game).release_year, extract(year from (p_game).release_date)::integer, public.catalog_title_year_hint((p_game).title)) as release_year_value
  from public.catalog_games seed
  left join public.games g on g.id = (p_game).master_game_id
  where seed.match_key = (p_game).match_key
  limit 1
)
select case
  when public.catalog_is_separate_game_type((select game_type from typed)) then 'separate:' || (p_game).match_key
  when nullif((p_game).master_game_id, '') is not null then 'igdb:' || (p_game).master_game_id
  when (select title_key from typed) <> '' and (select release_year_value from typed) is not null
    then 'title:' || (select title_key from typed) || ':' || (select release_year_value from typed)::text
  when (select title_key from typed) <> ''
    then 'title:' || (select title_key from typed)
  else 'game:' || (p_game).match_key
end;
$$;

create or replace function public.catalog_upsert_alias(
  p_alias_key text,
  p_canonical_key text,
  p_alias_kind text default 'legacy',
  p_source text default null,
  p_confidence numeric default 1.0,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alias text := nullif(trim(p_alias_key), '');
  v_canonical text := nullif(trim(p_canonical_key), '');
begin
  if v_alias is null or v_canonical is null or v_alias = v_canonical then
    return;
  end if;

  if not exists (select 1 from public.catalog_games where match_key = v_canonical) then
    return;
  end if;

  insert into public.catalog_game_aliases(alias_key, canonical_key, alias_kind, source, confidence, metadata)
  values (
    v_alias,
    v_canonical,
    coalesce(nullif(p_alias_kind, ''), 'legacy'),
    nullif(p_source, ''),
    greatest(0, least(coalesce(p_confidence, 1), 1)),
    coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (alias_key) do update set
    canonical_key = excluded.canonical_key,
    alias_kind = excluded.alias_kind,
    source = excluded.source,
    confidence = greatest(public.catalog_game_aliases.confidence, excluded.confidence),
    metadata = public.catalog_game_aliases.metadata || excluded.metadata;
end;
$$;

create or replace function public.catalog_resolve_seed_game(p_key text)
returns public.catalog_games
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '4s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_master_game_id text;
  v_game public.catalog_games%rowtype;
begin
  if v_key is null then
    return null;
  end if;

  select cg.* into v_game
  from public.catalog_game_aliases a
  join public.catalog_games cg on cg.match_key = a.canonical_key
  where a.alias_key = v_key
  order by a.confidence desc, a.updated_at desc
  limit 1;
  if found then return v_game; end if;

  select * into v_game
  from public.catalog_games cg
  where cg.match_key = v_key
  limit 1;
  if found then return v_game; end if;

  select * into v_game
  from public.catalog_games cg
  where cg.canonical_id = v_key
  order by public.catalog_is_master_catalog_game(cg) desc, cg.match_key
  limit 1;
  if found then return v_game; end if;

  v_master_game_id := public.resolve_master_game_id(v_key);
  if v_master_game_id is not null then
    select * into v_game
    from public.catalog_games cg
    where cg.master_game_id = v_master_game_id
    order by public.catalog_is_master_catalog_game(cg) desc, cg.match_key
    limit 1;
    if found then return v_game; end if;
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.store_listings @> jsonb_build_array(jsonb_build_object('listing_id', v_key))
  order by public.catalog_is_master_catalog_game(cg) desc, cg.match_key
  limit 1;
  if found then return v_game; end if;

  return null;
end;
$$;

create or replace function public.catalog_resolve_canonical_key(p_key text)
returns text
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '6s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_seed public.catalog_games%rowtype;
  v_seed_type text := 'unknown';
  v_title_key text;
  v_year integer;
  v_work_key text;
  v_result text;
begin
  if v_key is null then
    return null;
  end if;

  select a.canonical_key into v_result
  from public.catalog_game_aliases a
  where a.alias_key = v_key
  order by a.confidence desc, a.updated_at desc
  limit 1;
  if v_result is not null then
    return v_result;
  end if;

  v_seed := public.catalog_resolve_seed_game(v_key);
  if v_seed.match_key is null then
    return null;
  end if;

  select coalesce(g.game_type, 'unknown') into v_seed_type
  from public.games g
  where g.id = v_seed.master_game_id
  limit 1;
  v_seed_type := coalesce(v_seed_type, 'unknown');

  if public.catalog_is_separate_game_type(v_seed_type) then
    return v_seed.match_key;
  end if;

  v_title_key := public.catalog_editorial_base_title(v_seed.title);
  v_year := coalesce(v_seed.release_year, extract(year from v_seed.release_date)::integer, public.catalog_title_year_hint(v_seed.title));
  v_work_key := public.catalog_work_key_for_game(v_seed);

  with candidates as materialized (
    select
      cg.*,
      coalesce(g.game_type, 'unknown') as game_type,
      public.catalog_work_key_for_game(cg) as work_key,
      coalesce(cg.release_year, extract(year from cg.release_date)::integer, public.catalog_title_year_hint(cg.title)) as year_value,
      public.catalog_editorial_base_title(cg.title) as title_key,
      public.catalog_detail_media_count(cg.master_game_id) as media_count,
      public.catalog_review_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as review_count,
      public.catalog_library_anchor_count(cg.match_key, cg.canonical_id, cg.master_game_id) as library_count,
      (
        case when cg.release_date is not null then 1 else 0 end
        + case when nullif(cg.description, '') is not null then 1 else 0 end
        + case when nullif(cg.developer, '') is not null then 1 else 0 end
        + case when nullif(cg.publisher, '') is not null then 1 else 0 end
        + case when nullif(cg.image_url, '') is not null then 1 else 0 end
        + case when cardinality(coalesce(cg.platforms, '{}'::text[])) > 0 then 1 else 0 end
      ) as completeness_score
    from public.catalog_games cg
    left join public.games g on g.id = cg.master_game_id
    where not public.catalog_is_separate_game_type(coalesce(g.game_type, 'unknown'))
      and (
        public.catalog_work_key_for_game(cg) = v_work_key
        or (
          v_title_key <> ''
          and public.catalog_editorial_base_title(cg.title) = v_title_key
          and (
            v_year is null
            or coalesce(cg.release_year, extract(year from cg.release_date)::integer, public.catalog_title_year_hint(cg.title)) is null
            or abs(coalesce(cg.release_year, extract(year from cg.release_date)::integer, public.catalog_title_year_hint(cg.title)) - v_year) <= 2
          )
        )
      )
  )
  select c.match_key into v_result
  from candidates c
  order by
    c.review_count desc,
    c.library_count desc,
    c.media_count desc,
    public.catalog_is_master_catalog_game(c) desc,
    case c.source_kind when 'master' then 0 when 'hybrid' then 1 when 'catalog' then 2 else 3 end,
    c.completeness_score desc,
    c.release_date asc nulls last,
    c.match_key
  limit 1;

  return coalesce(v_result, v_seed.match_key);
end;
$$;

create or replace function public.catalog_register_canonical_aliases(p_key text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
declare
  v_seed public.catalog_games%rowtype;
  v_canonical_key text;
  v_registered integer := 0;
  v_listing jsonb;
begin
  v_seed := public.catalog_resolve_seed_game(p_key);
  if v_seed.match_key is null then
    return jsonb_build_object('canonical_key', null, 'registered', 0);
  end if;

  v_canonical_key := public.catalog_resolve_canonical_key(v_seed.match_key);
  if v_canonical_key is null then
    return jsonb_build_object('canonical_key', null, 'registered', 0);
  end if;

  perform public.catalog_upsert_alias(v_seed.match_key, v_canonical_key, 'legacy', v_seed.source_kind, 1, jsonb_build_object('registered_by', 'v5.6.0'));
  v_registered := v_registered + 1;

  if nullif(v_seed.canonical_id, '') is not null then
    perform public.catalog_upsert_alias(v_seed.canonical_id, v_canonical_key, 'canonical_id', v_seed.source_kind, 0.98, jsonb_build_object('registered_by', 'v5.6.0'));
    v_registered := v_registered + 1;
  end if;

  if nullif(v_seed.master_game_id, '') is not null then
    perform public.catalog_upsert_alias(v_seed.master_game_id, v_canonical_key, 'master', 'igdb', 1, jsonb_build_object('registered_by', 'v5.6.0'));
    perform public.catalog_upsert_alias('igdb:' || v_seed.master_game_id, v_canonical_key, 'master', 'igdb', 1, jsonb_build_object('registered_by', 'v5.6.0'));
    v_registered := v_registered + 2;
  end if;

  for v_listing in select value from jsonb_array_elements(coalesce(v_seed.store_listings, '[]'::jsonb))
  loop
    if jsonb_typeof(v_listing) = 'object' and nullif(v_listing ->> 'listing_id', '') is not null then
      perform public.catalog_upsert_alias(
        v_listing ->> 'listing_id',
        v_canonical_key,
        'listing',
        nullif(v_listing ->> 'store', ''),
        0.95,
        jsonb_build_object('registered_by', 'v5.6.0', 'listing', v_listing)
      );
      v_registered := v_registered + 1;

      insert into public.game_store_listings(
        canonical_key, store, listing_id, external_id, namespace, title, store_url, image_url,
        original_price, discount_price, currency_code, offer_type, category_group, metadata, last_seen_at
      )
      values (
        v_canonical_key,
        coalesce(nullif(v_listing ->> 'store', ''), 'unknown'),
        v_listing ->> 'listing_id',
        nullif(v_listing ->> 'external_id', ''),
        nullif(v_listing ->> 'namespace', ''),
        nullif(v_listing ->> 'title', ''),
        nullif(v_listing ->> 'store_url', ''),
        nullif(v_listing ->> 'image_url', ''),
        nullif(v_listing ->> 'original_price', '')::bigint,
        nullif(v_listing ->> 'discount_price', '')::bigint,
        nullif(v_listing ->> 'currency_code', ''),
        nullif(v_listing ->> 'offer_type', ''),
        nullif(v_listing ->> 'category_group', ''),
        v_listing,
        now()
      )
      on conflict (store, listing_id) do update set
        canonical_key = excluded.canonical_key,
        external_id = coalesce(excluded.external_id, public.game_store_listings.external_id),
        namespace = coalesce(excluded.namespace, public.game_store_listings.namespace),
        title = coalesce(excluded.title, public.game_store_listings.title),
        store_url = coalesce(excluded.store_url, public.game_store_listings.store_url),
        image_url = coalesce(excluded.image_url, public.game_store_listings.image_url),
        original_price = excluded.original_price,
        discount_price = excluded.discount_price,
        currency_code = coalesce(excluded.currency_code, public.game_store_listings.currency_code),
        offer_type = coalesce(excluded.offer_type, public.game_store_listings.offer_type),
        category_group = coalesce(excluded.category_group, public.game_store_listings.category_group),
        metadata = public.game_store_listings.metadata || excluded.metadata,
        last_seen_at = now();
    end if;
  end loop;

  return jsonb_build_object('canonical_key', v_canonical_key, 'registered', v_registered);
end;
$$;

create or replace function public.get_catalog_game(p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '8s'
as $$
declare
  v_key text := nullif(trim(p_key), '');
  v_match_key text;
  v_game public.catalog_games%rowtype;
  v_payload jsonb;
begin
  if v_key is null then
    return null;
  end if;

  v_match_key := public.catalog_resolve_canonical_key(v_key);
  if v_match_key is null then
    return null;
  end if;

  select * into v_game
  from public.catalog_games cg
  where cg.match_key = v_match_key
  limit 1;

  if not found then
    return null;
  end if;

  v_payload := public.catalog_game_card_json(v_game)
    || jsonb_build_object(
      'requested_key', v_key,
      'canonical_route_key', v_game.match_key,
      'canonical_work_key', public.catalog_work_key_for_game(v_game),
      'canonical_source', case when public.catalog_is_master_catalog_game(v_game) then 'igdb_master' else 'catalog_resolver' end,
      'is_canonical', true
    );

  return v_payload;
end;
$$;

create or replace function public.get_catalog_games(p_keys text[])
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '10s'
as $$
with requested as (
  select min(ord) as ord, key as requested_key
  from unnest(coalesce(p_keys, '{}'::text[])) with ordinality as keys(key, ord)
  where nullif(trim(key), '') is not null
  group by key
), resolved as (
  select r.ord, public.get_catalog_game(r.requested_key) as item
  from requested r
)
select coalesce(jsonb_agg(item order by ord) filter (where item is not null), '[]'::jsonb)
from resolved;
$$;

-- Search remains compatible with the existing RPC contract, but the returned
-- page is now deduplicated at canonical-work level. Raw store/catalog records
-- can still exist in catalog_games; they no longer need to be public search
-- results.
create or replace function public.search_catalog(
  p_query text default '',
  p_stores text[] default null,
  p_category text default null,
  p_segment text default null,
  p_price text default null,
  p_year integer default null,
  p_library_keys text[] default null,
  p_favorite_keys text[] default null,
  p_personal_filter text default null,
  p_sort text default 'relevance',
  p_limit integer default 36,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
declare
  v_q text := lower(trim(coalesce(p_query, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 36), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
  v_candidate_limit integer := least(5000, greatest(500, (greatest(0, coalesce(p_offset, 0)) + greatest(1, least(coalesce(p_limit, 36), 100))) * 28));
  v_candidate_keys text[] := '{}'::text[];
  v_candidate_limited boolean := false;
  v_result jsonb;
  v_has_filters boolean;
begin
  v_has_filters :=
    (p_stores is not null and cardinality(p_stores) > 0)
    or (p_category is not null and p_category not in ('', 'all'))
    or (p_segment is not null and p_segment not in ('', 'all'))
    or (p_price is not null and p_price not in ('', 'all'))
    or p_year is not null
    or (p_personal_filter is not null and p_personal_filter not in ('', 'all'));

  if v_q <> '' then
    select coalesce(array_agg(limited.match_key order by limited.relevance_score desc, limited.sort_title, limited.release_date asc nulls last, limited.match_key), '{}'::text[])
    into v_candidate_keys
    from (
      select deduped.match_key, deduped.relevance_score, deduped.sort_title, deduped.release_date
      from (
        select raw.match_key, max(raw.relevance_score)::real as relevance_score, min(raw.sort_title) as sort_title, min(raw.release_date) as release_date
        from (
          select cg.match_key,
            case
              when lower(cg.title) = v_q then 100::real
              when lower(cg.canonical_title) = v_q then 98::real
              when lower(cg.title) like v_q || '%' then 90::real
              when lower(cg.canonical_title) like v_q || '%' then 88::real
              else 72::real
            end as relevance_score,
            lower(cg.title) as sort_title,
            cg.release_date
          from public.catalog_games cg
          where lower(cg.title) like '%' || v_q || '%'
             or lower(cg.canonical_title) like '%' || v_q || '%'
        ) raw
        group by raw.match_key
      ) deduped
      order by deduped.relevance_score desc, deduped.sort_title, deduped.release_date asc nulls last, deduped.match_key
      limit v_candidate_limit
    ) limited;

    if cardinality(v_candidate_keys) = 0 and char_length(v_q) >= 4 then
      select coalesce(array_agg(limited.match_key order by limited.relevance_score desc, limited.sort_title, limited.release_date asc nulls last, limited.match_key), '{}'::text[])
      into v_candidate_keys
      from (
        select deduped.match_key, deduped.relevance_score, deduped.sort_title, deduped.release_date
        from (
          select raw.match_key, max(raw.relevance_score)::real as relevance_score, min(raw.sort_title) as sort_title, min(raw.release_date) as release_date
          from (
            select cg.match_key,
              greatest(extensions.similarity(lower(cg.title), v_q), extensions.similarity(lower(cg.canonical_title), v_q))::real * 25 + 35 as relevance_score,
              lower(cg.title) as sort_title,
              cg.release_date
            from public.catalog_games cg
            where lower(cg.title) operator(extensions.%) v_q
               or lower(cg.canonical_title) operator(extensions.%) v_q
          ) raw
          group by raw.match_key
        ) deduped
        order by deduped.relevance_score desc, deduped.sort_title, deduped.release_date asc nulls last, deduped.match_key
        limit least(v_candidate_limit, 1000)
      ) limited;
    end if;

    v_candidate_limited := cardinality(v_candidate_keys) >= v_candidate_limit;

    with candidate_keys as materialized (
      select keys.match_key, keys.relevance_rank
      from unnest(v_candidate_keys) with ordinality as keys(match_key, relevance_rank)
    ), eligible_raw as materialized (
      select cg.match_key, cg.title, cg.release_date, cg.sort_price, ck.relevance_rank
      from candidate_keys ck
      join public.catalog_games cg on cg.match_key = ck.match_key
      where
        (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
        and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
        and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
        and (p_year is null or cg.release_year = p_year)
        and (
          p_price is null or p_price = '' or p_price = 'all'
          or (p_price = 'free' and exists (
            select 1 from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
            where coalesce((listing ->> 'discount_price')::bigint, (listing ->> 'original_price')::bigint, 1) = 0
          ))
          or (p_price = 'discounted' and exists (
            select 1 from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
            where (listing ->> 'original_price') is not null and (listing ->> 'discount_price') is not null
              and (listing ->> 'discount_price')::bigint < (listing ->> 'original_price')::bigint
          ))
          or (p_price = 'paid' and cg.sort_price > 0)
        )
        and (
          p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
          or (p_personal_filter = 'saved' and (cg.match_key = any(coalesce(p_library_keys, '{}'::text[])) or cg.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))))
          or (p_personal_filter = 'favorite' and (cg.match_key = any(coalesce(p_favorite_keys, '{}'::text[])) or cg.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))))
        )
    ), resolved as materialized (
      select
        coalesce(public.catalog_resolve_canonical_key(er.match_key), er.match_key) as canonical_key,
        min(er.relevance_rank) as relevance_rank,
        min(er.title) as title,
        min(er.release_date) as release_date,
        max(er.sort_price) as sort_price
      from eligible_raw er
      group by coalesce(public.catalog_resolve_canonical_key(er.match_key), er.match_key)
    ), page_keys as materialized (
      select r.*
      from resolved r
      order by
        case when p_sort = 'title' then lower(r.title) end asc nulls last,
        case when p_sort = 'date' then r.release_date end desc nulls last,
        case when p_sort = 'value' then r.sort_price end desc nulls last,
        case when p_sort = 'relevance' or p_sort is null or p_sort = '' then r.relevance_rank end asc nulls last,
        lower(r.title), r.canonical_key
      limit v_limit offset v_offset
    ), page_payload as (
      select coalesce(jsonb_agg(public.get_catalog_game(pk.canonical_key)
        order by
          case when p_sort = 'title' then lower(pk.title) end asc nulls last,
          case when p_sort = 'date' then pk.release_date end desc nulls last,
          case when p_sort = 'value' then pk.sort_price end desc nulls last,
          case when p_sort = 'relevance' or p_sort is null or p_sort = '' then pk.relevance_rank end asc nulls last,
          lower(pk.title), pk.canonical_key
      ) filter (where public.get_catalog_game(pk.canonical_key) is not null), '[]'::jsonb) as items
      from page_keys pk
    )
    select jsonb_build_object(
      'items', page_payload.items,
      'total', (select count(*) from resolved),
      'canonical_total', (select count(*) from resolved),
      'limit', v_limit,
      'offset', v_offset,
      'has_more', v_offset + v_limit < (select count(*) from resolved),
      'candidate_limited', v_candidate_limited,
      'canonicalized', true
    )
    into v_result
    from page_payload;

    return coalesce(v_result, jsonb_build_object('items', '[]'::jsonb, 'total', 0, 'canonical_total', 0, 'limit', v_limit, 'offset', v_offset, 'has_more', false, 'candidate_limited', false, 'canonicalized', true));
  end if;

  -- Browse senza testo: mostra prima le proiezioni IGDB/master. I listing
  -- store rimangono raggiungibili come alias e disponibilità, non come opere.
  with eligible_raw as materialized (
    select cg.match_key, cg.title, cg.release_date, cg.sort_price
    from public.catalog_games cg
    where
      (not v_has_filters and public.catalog_is_master_catalog_game(cg)
        or v_has_filters)
      and (p_stores is null or cardinality(p_stores) = 0 or cg.stores && p_stores)
      and (p_category is null or p_category = '' or p_category = 'all' or cg.category_group = p_category)
      and (p_segment is null or p_segment = '' or p_segment = 'all' or cg.market_segment = p_segment)
      and (p_year is null or cg.release_year = p_year)
      and (
        p_price is null or p_price = '' or p_price = 'all'
        or (p_price = 'free' and exists (
          select 1 from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
          where coalesce((listing ->> 'discount_price')::bigint, (listing ->> 'original_price')::bigint, 1) = 0
        ))
        or (p_price = 'discounted' and exists (
          select 1 from jsonb_array_elements(coalesce(cg.store_listings, '[]'::jsonb)) listing
          where (listing ->> 'original_price') is not null and (listing ->> 'discount_price') is not null
            and (listing ->> 'discount_price')::bigint < (listing ->> 'original_price')::bigint
        ))
        or (p_price = 'paid' and cg.sort_price > 0)
      )
      and (
        p_personal_filter is null or p_personal_filter = '' or p_personal_filter = 'all'
        or (p_personal_filter = 'saved' and (cg.match_key = any(coalesce(p_library_keys, '{}'::text[])) or cg.canonical_id = any(coalesce(p_library_keys, '{}'::text[]))))
        or (p_personal_filter = 'favorite' and (cg.match_key = any(coalesce(p_favorite_keys, '{}'::text[])) or cg.canonical_id = any(coalesce(p_favorite_keys, '{}'::text[]))))
      )
  ), resolved as materialized (
    select
      coalesce(public.catalog_resolve_canonical_key(er.match_key), er.match_key) as canonical_key,
      min(er.title) as title,
      min(er.release_date) as release_date,
      max(er.sort_price) as sort_price
    from eligible_raw er
    group by coalesce(public.catalog_resolve_canonical_key(er.match_key), er.match_key)
  ), page_keys as materialized (
    select r.*
    from resolved r
    order by
      case when p_sort = 'date' then r.release_date end desc nulls last,
      case when p_sort = 'value' then r.sort_price end desc nulls last,
      lower(r.title), r.canonical_key
    limit v_limit offset v_offset
  ), page_payload as (
    select coalesce(jsonb_agg(public.get_catalog_game(pk.canonical_key)
      order by
        case when p_sort = 'date' then pk.release_date end desc nulls last,
        case when p_sort = 'value' then pk.sort_price end desc nulls last,
        lower(pk.title), pk.canonical_key
    ) filter (where public.get_catalog_game(pk.canonical_key) is not null), '[]'::jsonb) as items
    from page_keys pk
  )
  select jsonb_build_object(
    'items', page_payload.items,
    'total', (select count(*) from resolved),
    'canonical_total', (select count(*) from resolved),
    'limit', v_limit,
    'offset', v_offset,
    'has_more', v_offset + v_limit < (select count(*) from resolved),
    'candidate_limited', false,
    'canonicalized', true
  )
  into v_result
  from page_payload;

  return coalesce(v_result, jsonb_build_object('items', '[]'::jsonb, 'total', 0, 'canonical_total', 0, 'limit', v_limit, 'offset', v_offset, 'has_more', false, 'candidate_limited', false, 'canonicalized', true));
end;
$$;

revoke all on table public.catalog_game_aliases from public;
revoke all on table public.game_store_listings from public;
grant select on table public.catalog_game_aliases to authenticated, service_role;
grant select on table public.game_store_listings to anon, authenticated, service_role;

revoke all on function public.catalog_is_master_catalog_game(public.catalog_games) from public;
revoke all on function public.catalog_work_key_for_game(public.catalog_games) from public;
revoke all on function public.catalog_upsert_alias(text, text, text, text, numeric, jsonb) from public;
revoke all on function public.catalog_resolve_seed_game(text) from public;
revoke all on function public.catalog_resolve_canonical_key(text) from public;
revoke all on function public.catalog_register_canonical_aliases(text) from public;
revoke all on function public.get_catalog_game(text) from public;
revoke all on function public.get_catalog_games(text[]) from public;
revoke all on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) from public;

grant execute on function public.catalog_resolve_canonical_key(text) to anon, authenticated, service_role;
grant execute on function public.catalog_register_canonical_aliases(text) to authenticated, service_role;
grant execute on function public.get_catalog_game(text) to anon, authenticated;
grant execute on function public.get_catalog_games(text[]) to anon, authenticated;
grant execute on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) to anon, authenticated;

comment on table public.catalog_game_aliases is
'Ludograph v5.6.0: alias/redirect da chiavi legacy, store e listing verso la scheda gioco canonica.';
comment on table public.game_store_listings is
'Ludograph v5.6.0: disponibilità store collegata alla scheda canonica; Steam/Epic/PSN non sono più cataloghi paralleli.';
comment on function public.catalog_resolve_canonical_key(text) is
'Ludograph v5.6.0: risolve qualunque chiave catalogo/store/legacy verso il match_key canonico, preferendo IGDB/master e contenuti ricchi.';
comment on function public.search_catalog(text, text[], text, text, text, integer, text[], text[], text, text, integer, integer) is
'Ludograph v5.6.0: ricerca pubblica su opere canoniche; gli store restano listing aggregati e alias.';

commit;

notify pgrst, 'reload schema';
