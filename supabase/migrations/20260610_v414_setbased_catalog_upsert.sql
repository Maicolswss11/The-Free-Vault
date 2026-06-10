-- The Free Vault v4.1.4 — upsert catalogo set-based.
-- Eseguire dopo 20260610_v413_incremental_catalog_sync.sql.
--
-- Sostituisce il loop PL/pgSQL riga-per-riga con una pipeline set-based:
--   jsonb_to_recordset -> dedup listing -> merge per match_key -> preclassifica
--   -> INSERT ... ON CONFLICT DO UPDATE solo per righe realmente cambiate.

create or replace function public.catalog_safe_date(p_value text)
returns date
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  if p_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    return null;
  end if;

  return p_value::date;
exception
  when others then
    return null;
end;
$$;

revoke all on function public.catalog_safe_date(text) from public;
grant execute on function public.catalog_safe_date(text) to service_role;

create or replace function public.upsert_catalog_games_incremental(
  p_store text,
  p_run_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '60s'
as $$
declare
  v_processed bigint;
  v_result jsonb;
begin
  if p_store is null or p_store not in (
    'epic', 'steam', 'playstation', 'xbox', 'nintendo', 'other'
  ) then
    raise exception 'Store non valido: %', p_store;
  end if;

  if p_run_id is null then
    raise exception 'p_run_id non può essere nullo';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows deve essere un array JSON';
  end if;

  v_processed := jsonb_array_length(p_rows);

  if v_processed = 0 then
    return jsonb_build_object(
      'processed', 0,
      'processed_games', 0,
      'inserted_games', 0,
      'updated_games', 0,
      'unchanged_games', 0,
      'applied_games', 0
    );
  end if;

  -- Reject malformed/mixed-store batches instead of silently discarding rows.
  if exists (
    select 1
    from jsonb_array_elements(p_rows) as x(elem)
    where jsonb_typeof(x.elem) <> 'object'
      or jsonb_typeof(x.elem -> 'listing') <> 'object'
      or nullif(btrim(x.elem ->> 'match_key'), '') is null
      or nullif(btrim(x.elem -> 'listing' ->> 'listing_id'), '') is null
      or (x.elem -> 'listing' ->> 'store') is distinct from p_store
  ) then
    raise exception 'Il batch contiene righe malformate o listing non appartenenti allo store %', p_store;
  end if;

  with
  input_raw as materialized (
    select
      nullif(btrim(v.match_key), '') as match_key,
      nullif(btrim(v.canonical_id), '') as canonical_id,
      nullif(btrim(v.title), '') as title,
      nullif(btrim(v.canonical_title), '') as canonical_title,
      nullif(btrim(v.description), '') as description,
      nullif(btrim(v.developer), '') as developer,
      nullif(btrim(v.publisher), '') as publisher,
      nullif(btrim(v.image_url), '') as image_url,
      nullif(btrim(v.store_url), '') as store_url,
      public.catalog_safe_date(nullif(btrim(v.release_date), '')) as release_date,
      v.release_year,
      nullif(btrim(v.market_segment), '') as market_segment,
      nullif(btrim(v.category_group), '') as category_group,
      nullif(btrim(v.offer_type), '') as offer_type,
      v.platforms as platforms_jsonb,
      v.genres as genres_jsonb,
      v.categories as categories_jsonb,
      v.listing as listing_payload,
      nullif(btrim(v.listing ->> 'store'), '') as listing_store,
      nullif(btrim(v.listing ->> 'listing_id'), '') as listing_id,
      nullif(btrim(v.source_hash), '') as source_hash
    from jsonb_to_recordset(p_rows) as v(
      match_key text,
      canonical_id text,
      title text,
      canonical_title text,
      description text,
      developer text,
      publisher text,
      image_url text,
      store_url text,
      release_date text,
      release_year integer,
      market_segment text,
      category_group text,
      offer_type text,
      platforms jsonb,
      genres jsonb,
      categories jsonb,
      listing jsonb,
      source_hash text
    )
  ),

  input_parsed as materialized (
    select
      r.*,
      array(
        select distinct value
        from jsonb_array_elements_text(
          case
            when jsonb_typeof(r.platforms_jsonb) = 'array' then r.platforms_jsonb
            else '[]'::jsonb
          end
        ) as p(value)
        where nullif(btrim(value), '') is not null
        order by value
      ) as platforms,
      array(
        select distinct value
        from jsonb_array_elements_text(
          case
            when jsonb_typeof(r.genres_jsonb) = 'array' then r.genres_jsonb
            else '[]'::jsonb
          end
        ) as g(value)
        where nullif(btrim(value), '') is not null
        order by value
      ) as genres,
      array(
        select distinct value
        from jsonb_array_elements_text(
          case
            when jsonb_typeof(r.categories_jsonb) = 'array' then r.categories_jsonb
            else '[]'::jsonb
          end
        ) as c(value)
        where nullif(btrim(value), '') is not null
        order by value
      ) as categories
    from input_raw r
  ),

  -- A batch can contain several AppIDs/editions for the same canonical game.
  -- First deduplicate exact store listings deterministically.
  input_dedup as materialized (
    select distinct on (match_key, listing_store, listing_id)
      p.*
    from input_parsed p
    order by
      match_key,
      listing_store,
      listing_id,
      source_hash desc nulls last,
      listing_payload::text desc
  ),

  input_games as materialized (
    select distinct match_key
    from input_dedup
  ),

  existing as materialized (
    select cg.*
    from public.catalog_games cg
    join input_games ig on ig.match_key = cg.match_key
  ),

  representative_ranked as materialized (
    select
      d.*,
      row_number() over (
        partition by d.match_key
        order by
          (
            case when d.title is not null then 1 else 0 end
            + case when d.canonical_title is not null then 1 else 0 end
            + case when d.description is not null then 1 else 0 end
            + case when d.developer is not null then 1 else 0 end
            + case when d.publisher is not null then 1 else 0 end
            + case when d.image_url is not null then 1 else 0 end
            + case when d.release_date is not null then 1 else 0 end
            + case when cardinality(d.genres) > 0 then 1 else 0 end
          ) desc,
          d.source_hash desc nulls last,
          d.listing_store,
          d.listing_id,
          d.listing_payload::text
      ) as representative_rank
    from input_dedup d
  ),

  representative as materialized (
    select *
    from representative_ranked
    where representative_rank = 1
  ),

  existing_listings as materialized (
    select
      e.match_key,
      nullif(btrim(item ->> 'store'), '') as listing_store,
      nullif(btrim(item ->> 'listing_id'), '') as listing_id,
      item as listing_payload,
      0 as source_priority,
      null::text as source_hash
    from existing e
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(e.store_listings) = 'array' then e.store_listings
        else '[]'::jsonb
      end
    ) as old(item)
    where jsonb_typeof(item) = 'object'
      and nullif(btrim(item ->> 'store'), '') is not null
      and nullif(btrim(item ->> 'listing_id'), '') is not null
  ),

  incoming_listings as materialized (
    select
      d.match_key,
      d.listing_store,
      d.listing_id,
      d.listing_payload,
      1 as source_priority,
      d.source_hash
    from input_dedup d
  ),

  all_listings as materialized (
    select * from existing_listings
    union all
    select * from incoming_listings
  ),

  ranked_listings as materialized (
    select
      a.*,
      row_number() over (
        partition by a.match_key, a.listing_store, a.listing_id
        order by
          a.source_priority desc,
          a.source_hash desc nulls last,
          a.listing_payload::text desc
      ) as listing_rank
    from all_listings a
  ),

  merged_listings as materialized (
    select
      r.match_key,
      jsonb_agg(
        r.listing_payload
        order by r.listing_store, r.listing_id
      ) as store_listings,
      array_agg(
        distinct r.listing_store
        order by r.listing_store
      ) as stores,
      coalesce(
        max(
          greatest(
            case
              when r.listing_payload ->> 'original_price' ~ '^[0-9]+$'
                then (r.listing_payload ->> 'original_price')::bigint
              else 0
            end,
            case
              when r.listing_payload ->> 'discount_price' ~ '^[0-9]+$'
                then (r.listing_payload ->> 'discount_price')::bigint
              else 0
            end
          )
        ),
        0
      )::bigint as sort_price
    from ranked_listings r
    where r.listing_rank = 1
    group by r.match_key
  ),

  metadata_base as materialized (
    select
      ig.match_key,
      (e.match_key is not null) as had_row,
      (
        e.match_key is not null
        and p_store <> 'epic'
        and 'epic' = any(e.stores)
      ) as preserve_existing_epic,

      e.canonical_id as old_canonical_id,
      e.title as old_title,
      e.canonical_title as old_canonical_title,
      e.description as old_description,
      e.developer as old_developer,
      e.publisher as old_publisher,
      e.image_url as old_image_url,
      e.store_url as old_store_url,
      e.release_date as old_release_date,
      e.release_year as old_release_year,
      e.market_segment as old_market_segment,
      e.category_group as old_category_group,
      e.offer_type as old_offer_type,
      e.platforms as old_platforms,
      e.genres as old_genres,
      e.categories as old_categories,
      e.stores as old_stores,
      e.store_listings as old_store_listings,
      e.sort_price as old_sort_price,

      r.canonical_id as new_canonical_id,
      r.title as new_title,
      r.canonical_title as new_canonical_title,
      r.description as new_description,
      r.developer as new_developer,
      r.publisher as new_publisher,
      r.image_url as new_image_url,
      r.store_url as new_store_url,
      r.release_date as new_release_date,
      r.release_year as new_release_year,
      r.market_segment as new_market_segment,
      r.category_group as new_category_group,
      r.offer_type as new_offer_type,
      r.platforms as new_platforms,
      r.genres as new_genres,
      r.categories as new_categories,

      m.stores as merged_stores,
      m.store_listings as merged_store_listings,
      m.sort_price as merged_sort_price
    from input_games ig
    join representative r on r.match_key = ig.match_key
    join merged_listings m on m.match_key = ig.match_key
    left join existing e on e.match_key = ig.match_key
  ),

  final_fields as materialized (
    select
      b.match_key,
      b.had_row,

      case
        when b.preserve_existing_epic then b.old_canonical_id
        else coalesce(b.new_canonical_id, b.old_canonical_id, b.match_key)
      end as canonical_id,

      case
        when b.preserve_existing_epic then b.old_title
        else coalesce(b.new_title, b.old_title, b.new_canonical_title, b.match_key)
      end as title,

      case
        when b.preserve_existing_epic then b.old_canonical_title
        else coalesce(b.new_canonical_title, b.old_canonical_title, b.new_title, b.match_key)
      end as canonical_title,

      case
        when b.preserve_existing_epic then b.old_description
        else coalesce(b.new_description, b.old_description)
      end as description,

      case
        when b.preserve_existing_epic then b.old_developer
        else coalesce(b.new_developer, b.old_developer)
      end as developer,

      case
        when b.preserve_existing_epic then b.old_publisher
        else coalesce(b.new_publisher, b.old_publisher)
      end as publisher,

      case
        when b.preserve_existing_epic then b.old_image_url
        else coalesce(b.new_image_url, b.old_image_url)
      end as image_url,

      case
        when b.preserve_existing_epic then b.old_store_url
        else coalesce(b.new_store_url, b.old_store_url)
      end as store_url,

      case
        when b.preserve_existing_epic then b.old_release_date
        else coalesce(b.new_release_date, b.old_release_date)
      end as release_date,

      case
        when b.preserve_existing_epic then b.old_release_year
        else coalesce(b.new_release_year, b.old_release_year)
      end as release_year,

      case
        when b.preserve_existing_epic then coalesce(b.old_market_segment, 'unclassified')
        when b.new_market_segment is null or b.new_market_segment = 'unclassified'
          then coalesce(b.old_market_segment, 'unclassified')
        else b.new_market_segment
      end as market_segment,

      case
        when b.preserve_existing_epic then coalesce(b.old_category_group, 'other')
        when b.new_category_group is null or b.new_category_group = 'other'
          then coalesce(b.old_category_group, 'other')
        else b.new_category_group
      end as category_group,

      case
        when b.preserve_existing_epic then b.old_offer_type
        else coalesce(b.new_offer_type, b.old_offer_type)
      end as offer_type,

      case
        when b.preserve_existing_epic then coalesce(b.old_platforms, '{}'::text[])
        when cardinality(b.new_platforms) > 0 then b.new_platforms
        else coalesce(b.old_platforms, '{}'::text[])
      end as platforms,

      case
        when b.preserve_existing_epic then coalesce(b.old_genres, '{}'::text[])
        when cardinality(b.new_genres) > 0 then b.new_genres
        else coalesce(b.old_genres, '{}'::text[])
      end as genres,

      case
        when b.preserve_existing_epic then coalesce(b.old_categories, '{}'::text[])
        when cardinality(b.new_categories) > 0 then b.new_categories
        else coalesce(b.old_categories, '{}'::text[])
      end as categories,

      coalesce(b.merged_stores, '{}'::text[]) as stores,
      coalesce(b.merged_store_listings, '[]'::jsonb) as store_listings,
      coalesce(b.merged_sort_price, 0)::bigint as sort_price,

      b.old_canonical_id,
      b.old_title,
      b.old_canonical_title,
      b.old_description,
      b.old_developer,
      b.old_publisher,
      b.old_image_url,
      b.old_store_url,
      b.old_release_date,
      b.old_release_year,
      b.old_market_segment,
      b.old_category_group,
      b.old_offer_type,
      b.old_platforms,
      b.old_genres,
      b.old_categories,
      b.old_stores,
      b.old_store_listings,
      b.old_sort_price
    from metadata_base b
  ),

  preclassified as materialized (
    select
      f.*,
      case
        when not f.had_row then true
        else (
          f.old_canonical_id is distinct from f.canonical_id
          or f.old_title is distinct from f.title
          or f.old_canonical_title is distinct from f.canonical_title
          or f.old_description is distinct from f.description
          or f.old_developer is distinct from f.developer
          or f.old_publisher is distinct from f.publisher
          or f.old_image_url is distinct from f.image_url
          or f.old_store_url is distinct from f.store_url
          or f.old_release_date is distinct from f.release_date
          or f.old_release_year is distinct from f.release_year
          or f.old_market_segment is distinct from f.market_segment
          or f.old_category_group is distinct from f.category_group
          or f.old_offer_type is distinct from f.offer_type
          or f.old_platforms is distinct from f.platforms
          or f.old_genres is distinct from f.genres
          or f.old_categories is distinct from f.categories
          or f.old_stores is distinct from f.stores
          or f.old_store_listings is distinct from f.store_listings
          or f.old_sort_price is distinct from f.sort_price
        )
      end as would_change
    from final_fields f
  ),

  upsert_source as materialized (
    select *
    from preclassified
    where not had_row or would_change
  ),

  do_upsert as (
    insert into public.catalog_games as cg (
      match_key,
      canonical_id,
      title,
      canonical_title,
      description,
      developer,
      publisher,
      image_url,
      store_url,
      release_date,
      release_year,
      market_segment,
      category_group,
      offer_type,
      platforms,
      genres,
      categories,
      stores,
      store_listings,
      sort_price,
      index_run_id,
      updated_at
    )
    select
      u.match_key,
      u.canonical_id,
      u.title,
      u.canonical_title,
      u.description,
      u.developer,
      u.publisher,
      u.image_url,
      u.store_url,
      u.release_date,
      u.release_year,
      u.market_segment,
      u.category_group,
      u.offer_type,
      u.platforms,
      u.genres,
      u.categories,
      u.stores,
      u.store_listings,
      u.sort_price,
      p_run_id,
      now()
    from upsert_source u
    on conflict (match_key) do update
    set
      canonical_id = excluded.canonical_id,
      title = excluded.title,
      canonical_title = excluded.canonical_title,
      description = excluded.description,
      developer = excluded.developer,
      publisher = excluded.publisher,
      image_url = excluded.image_url,
      store_url = excluded.store_url,
      release_date = excluded.release_date,
      release_year = excluded.release_year,
      market_segment = excluded.market_segment,
      category_group = excluded.category_group,
      offer_type = excluded.offer_type,
      platforms = excluded.platforms,
      genres = excluded.genres,
      categories = excluded.categories,
      stores = excluded.stores,
      store_listings = excluded.store_listings,
      sort_price = excluded.sort_price,
      index_run_id = excluded.index_run_id,
      updated_at = excluded.updated_at
    where
      cg.canonical_id is distinct from excluded.canonical_id
      or cg.title is distinct from excluded.title
      or cg.canonical_title is distinct from excluded.canonical_title
      or cg.description is distinct from excluded.description
      or cg.developer is distinct from excluded.developer
      or cg.publisher is distinct from excluded.publisher
      or cg.image_url is distinct from excluded.image_url
      or cg.store_url is distinct from excluded.store_url
      or cg.release_date is distinct from excluded.release_date
      or cg.release_year is distinct from excluded.release_year
      or cg.market_segment is distinct from excluded.market_segment
      or cg.category_group is distinct from excluded.category_group
      or cg.offer_type is distinct from excluded.offer_type
      or cg.platforms is distinct from excluded.platforms
      or cg.genres is distinct from excluded.genres
      or cg.categories is distinct from excluded.categories
      or cg.stores is distinct from excluded.stores
      or cg.store_listings is distinct from excluded.store_listings
      or cg.sort_price is distinct from excluded.sort_price
    returning cg.match_key
  )
  select jsonb_build_object(
    'processed', v_processed,
    'processed_games', count(*)::bigint,
    'inserted_games', (count(*) filter (where not had_row))::bigint,
    'updated_games', (count(*) filter (where had_row and would_change))::bigint,
    'unchanged_games', (count(*) filter (where had_row and not would_change))::bigint,
    'applied_games', (select count(*)::bigint from do_upsert)
  )
  into v_result
  from preclassified;

  return coalesce(
    v_result,
    jsonb_build_object(
      'processed', v_processed,
      'processed_games', 0,
      'inserted_games', 0,
      'updated_games', 0,
      'unchanged_games', 0,
      'applied_games', 0
    )
  );
end;
$$;

revoke all on function public.upsert_catalog_games_incremental(text, uuid, jsonb) from public;
grant execute on function public.upsert_catalog_games_incremental(text, uuid, jsonb) to service_role;

comment on function public.upsert_catalog_games_incremental(text, uuid, jsonb) is
'Set-based incremental catalog merge. Deduplicates store listings per match_key/store/listing_id and avoids writes for unchanged canonical games.';
