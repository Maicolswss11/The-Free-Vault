-- The Free Vault v4.4 — Discovery avanzata
-- Aggiunge sezioni curate, pagine sviluppatore/publisher e giochi correlati.
-- Non crea nuove tabelle né indici pesanti.

create or replace function public.catalog_game_card_json(p_game public.catalog_games)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'canonical_id', (p_game).canonical_id,
    'match_key', (p_game).match_key,
    'internal_id', (p_game).canonical_id,
    'listing_id', ((p_game).store_listings -> 0 ->> 'listing_id'),
    'source_kind', 'catalog',
    'store', ((p_game).store_listings -> 0 ->> 'store'),
    'stores', to_jsonb((p_game).stores),
    'store_listings', (p_game).store_listings,
    'title', (p_game).title,
    'canonical_title', (p_game).canonical_title,
    'description', (p_game).description,
    'developer', (p_game).developer,
    'publisher', (p_game).publisher,
    'image_url', (p_game).image_url,
    'store_url', (p_game).store_url,
    'release_date', (p_game).release_date,
    'release_year', (p_game).release_year,
    'market_segment', (p_game).market_segment,
    'category_group', (p_game).category_group,
    'offer_type', (p_game).offer_type,
    'platforms', to_jsonb((p_game).platforms),
    'genres', to_jsonb((p_game).genres),
    'categories', to_jsonb((p_game).categories),
    'original_price', ((p_game).store_listings -> 0 -> 'original_price'),
    'discount_price', ((p_game).store_listings -> 0 -> 'discount_price'),
    'currency_code', ((p_game).store_listings -> 0 ->> 'currency_code'),
    'fmt_original_price', ((p_game).store_listings -> 0 ->> 'fmt_original_price'),
    'fmt_discount_price', ((p_game).store_listings -> 0 ->> 'fmt_discount_price')
  );
$$;

revoke all on function public.catalog_game_card_json(public.catalog_games) from public;

create or replace function public.catalog_discovery(p_limit integer default 12)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
with params as (
  select greatest(4, least(coalesce(p_limit, 12), 24)) as item_limit
),
public_review_scores as materialized (
  select
    gr.game_key,
    count(*)::integer as review_count,
    round(avg(gr.rating)::numeric, 2) as average_rating
  from public.game_reviews gr
  where public.can_view_user_content(gr.user_id, 'activity')
  group by gr.game_key
),
resolved_scores as materialized (
  select
    prs.review_count,
    prs.average_rating,
    cg.match_key
  from public_review_scores prs
  join lateral (
    select candidate.match_key
    from public.catalog_games candidate
    where candidate.match_key = prs.game_key
       or candidate.canonical_id = prs.game_key
    order by case when candidate.match_key = prs.game_key then 0 else 1 end
    limit 1
  ) cg on true
),
recent_keys as materialized (
  select recent_game.match_key
  from public.catalog_games recent_game
  where recent_game.category_group = 'base_game'
    and recent_game.release_date is not null
    and recent_game.release_date <= current_date
    and recent_game.image_url is not null
  order by recent_game.release_date desc, recent_game.match_key
  limit (select item_limit from params)
),
multi_store_keys as materialized (
  select multi_game.match_key
  from public.catalog_games multi_game
  where multi_game.stores @> array['epic', 'steam']::text[]
    and multi_game.category_group = 'base_game'
    and multi_game.image_url is not null
  order by multi_game.release_date desc nulls last, multi_game.match_key
  limit (select item_limit from params)
),
indie_keys as materialized (
  select indie_game.match_key
  from public.catalog_games indie_game
  where indie_game.market_segment = 'indie'
    and indie_game.category_group = 'base_game'
    and indie_game.image_url is not null
  order by indie_game.release_date desc nulls last, indie_game.match_key
  limit (select item_limit from params)
),
top_rated_keys as materialized (
  select rs.match_key, rs.review_count, rs.average_rating
  from resolved_scores rs
  order by rs.average_rating desc, rs.review_count desc, rs.match_key
  limit (select item_limit from params)
),
most_reviewed_keys as materialized (
  select rs.match_key, rs.review_count, rs.average_rating
  from resolved_scores rs
  order by rs.review_count desc, rs.average_rating desc, rs.match_key
  limit (select item_limit from params)
)
select jsonb_build_object(
  'generated_at', now(),
  'recent', coalesce((
    select jsonb_agg(public.catalog_game_card_json(cg) order by cg.release_date desc nulls last, lower(cg.title), cg.match_key)
    from recent_keys rk
    join public.catalog_games cg on cg.match_key = rk.match_key
  ), '[]'::jsonb),
  'community_top', coalesce((
    select jsonb_agg(
      public.catalog_game_card_json(cg)
      || jsonb_build_object(
        'average_rating', trk.average_rating,
        'review_count', trk.review_count
      )
      order by trk.average_rating desc, trk.review_count desc, cg.match_key
    )
    from top_rated_keys trk
    join public.catalog_games cg on cg.match_key = trk.match_key
  ), '[]'::jsonb),
  'most_reviewed', coalesce((
    select jsonb_agg(
      public.catalog_game_card_json(cg)
      || jsonb_build_object(
        'average_rating', mrk.average_rating,
        'review_count', mrk.review_count
      )
      order by mrk.review_count desc, mrk.average_rating desc, cg.match_key
    )
    from most_reviewed_keys mrk
    join public.catalog_games cg on cg.match_key = mrk.match_key
  ), '[]'::jsonb),
  'multi_store', coalesce((
    select jsonb_agg(public.catalog_game_card_json(cg) order by cg.release_date desc nulls last, lower(cg.title), cg.match_key)
    from multi_store_keys msk
    join public.catalog_games cg on cg.match_key = msk.match_key
  ), '[]'::jsonb),
  'indie', coalesce((
    select jsonb_agg(public.catalog_game_card_json(cg) order by cg.release_date desc nulls last, lower(cg.title), cg.match_key)
    from indie_keys ik
    join public.catalog_games cg on cg.match_key = ik.match_key
  ), '[]'::jsonb)
);
$$;

revoke all on function public.catalog_discovery(integer) from public;
grant execute on function public.catalog_discovery(integer) to anon, authenticated;

create or replace function public.catalog_entity(
  p_kind text,
  p_name text,
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
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_name text := trim(coalesce(p_name, ''));
  v_limit integer := greatest(1, least(coalesce(p_limit, 36), 100));
  v_offset integer := greatest(0, coalesce(p_offset, 0));
begin
  if v_kind not in ('developer', 'publisher') then
    raise exception 'Unsupported catalog entity kind: %', v_kind;
  end if;

  if v_name = '' then
    return jsonb_build_object(
      'kind', v_kind,
      'name', v_name,
      'total', 0,
      'limit', v_limit,
      'offset', v_offset,
      'items', '[]'::jsonb
    );
  end if;

  return (
    with filtered as materialized (
      select cg.match_key
      from public.catalog_games cg
      where (
        (v_kind = 'developer' and lower(coalesce(cg.developer, '')) = lower(v_name))
        or
        (v_kind = 'publisher' and lower(coalesce(cg.publisher, '')) = lower(v_name))
      )
      and (
        cg.search_document @@ plainto_tsquery('simple', v_name)
        or lower(cg.title) = lower(v_name)
      )
    ),
    page_keys as materialized (
      select cg.match_key
      from filtered f
      join public.catalog_games cg on cg.match_key = f.match_key
      order by cg.release_date desc nulls last, lower(cg.title), cg.match_key
      limit v_limit
      offset v_offset
    )
    select jsonb_build_object(
      'kind', v_kind,
      'name', v_name,
      'total', (select count(*) from filtered),
      'limit', v_limit,
      'offset', v_offset,
      'items', coalesce((
        select jsonb_agg(
          public.catalog_game_card_json(cg)
          order by cg.release_date desc nulls last, lower(cg.title), cg.match_key
        )
        from page_keys pk
        join public.catalog_games cg on cg.match_key = pk.match_key
      ), '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.catalog_entity(text, text, integer, integer) from public;
grant execute on function public.catalog_entity(text, text, integer, integer) to anon, authenticated;

create or replace function public.catalog_related_games(
  p_key text,
  p_limit integer default 12
)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
with params as (
  select greatest(1, least(coalesce(p_limit, 12), 24)) as item_limit
),
target as materialized (
  select cg.*
  from public.catalog_games cg
  where cg.match_key = p_key
     or cg.canonical_id = p_key
     or exists (
       select 1
       from jsonb_array_elements(cg.store_listings) listing
       where listing ->> 'listing_id' = p_key
     )
  order by case when cg.match_key = p_key then 0 when cg.canonical_id = p_key then 1 else 2 end
  limit 1
),
developer_candidates as materialized (
  select cg.match_key
  from target t
  join public.catalog_games cg
    on t.developer is not null
   and t.developer <> ''
   and lower(cg.developer) = lower(t.developer)
   and cg.search_document @@ plainto_tsquery('simple', t.developer)
  where cg.match_key <> t.match_key
  order by cg.release_date desc nulls last, cg.match_key
  limit 80
),
publisher_candidates as materialized (
  select cg.match_key
  from target t
  join public.catalog_games cg
    on t.publisher is not null
   and t.publisher <> ''
   and lower(cg.publisher) = lower(t.publisher)
   and cg.search_document @@ plainto_tsquery('simple', t.publisher)
  where cg.match_key <> t.match_key
  order by cg.release_date desc nulls last, cg.match_key
  limit 80
),
category_candidates as materialized (
  select cg.match_key
  from target t
  join public.catalog_games cg
    on cg.category_group = t.category_group
   and (
     t.release_year is null
     or cg.release_year between t.release_year - 3 and t.release_year + 3
   )
  where cg.match_key <> t.match_key
  order by cg.release_date desc nulls last, cg.match_key
  limit 100
),
candidate_keys as materialized (
  select match_key from developer_candidates
  union
  select match_key from publisher_candidates
  union
  select match_key from category_candidates
),
scored as materialized (
  select
    cg.match_key,
    (
      case when t.developer is not null and lower(cg.developer) = lower(t.developer) then 10 else 0 end
      + case when t.publisher is not null and lower(cg.publisher) = lower(t.publisher) then 7 else 0 end
      + case when cg.category_group = t.category_group then 3 else 0 end
      + case when cg.market_segment = t.market_segment then 2 else 0 end
      + case when cg.stores && t.stores then 1 else 0 end
      + greatest(
          0,
          4 - coalesce(abs(cg.release_year - t.release_year), 4)
        )
      + least(
          6,
          cardinality(array(
            select genre
            from unnest(cg.genres) genre
            intersect
            select target_genre
            from unnest(t.genres) target_genre
          )) * 2
        )
    )::integer as relation_score
  from candidate_keys ck
  join public.catalog_games cg on cg.match_key = ck.match_key
  cross join target t
)
select coalesce(jsonb_agg(
  public.catalog_game_card_json(cg)
  || jsonb_build_object('relation_score', s.relation_score)
  order by s.relation_score desc, cg.release_date desc nulls last, lower(cg.title), cg.match_key
), '[]'::jsonb)
from (
  select scored.*
  from scored
  order by relation_score desc, match_key
  limit (select item_limit from params)
) s
join public.catalog_games cg on cg.match_key = s.match_key;
$$;

revoke all on function public.catalog_related_games(text, integer) from public;
grant execute on function public.catalog_related_games(text, integer) to anon, authenticated;

comment on function public.catalog_discovery(integer) is
'Lightweight discovery sections built from the canonical catalog and public reviews.';

comment on function public.catalog_entity(text, text, integer, integer) is
'Paginated exact developer or publisher page without exposing catalog tables.';

comment on function public.catalog_related_games(text, integer) is
'Bounded related-games query based on developer, publisher, genre, category and release year.';
