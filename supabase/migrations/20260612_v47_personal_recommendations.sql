-- The Free Vault v4.7 — Raccomandazioni personali e inserimento multiplo nelle saghe.
-- Eseguire dopo la v4.6.
-- Non crea nuove tabelle, copie del catalogo o indici: usa esclusivamente dati già presenti.

create or replace function public.admin_save_franchise_games_batch(
  p_franchise_id uuid,
  p_games jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_item jsonb;
  v_key text;
  v_relation_type text;
  v_release_order integer;
  v_narrative_order integer;
  v_note text;
  v_count integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if p_games is null or jsonb_typeof(p_games) <> 'array' or jsonb_array_length(p_games) = 0 then
    raise exception 'Seleziona almeno un gioco';
  end if;

  if jsonb_array_length(p_games) > 100 then
    raise exception 'Puoi aggiungere al massimo 100 giochi per volta';
  end if;

  for v_item in select value from jsonb_array_elements(p_games)
  loop
    v_key := trim(coalesce(v_item ->> 'game_key', ''));
    v_relation_type := coalesce(nullif(trim(v_item ->> 'relation_type'), ''), 'main');
    v_release_order := nullif(v_item ->> 'release_order', '')::integer;
    v_narrative_order := nullif(v_item ->> 'narrative_order', '')::integer;
    v_note := nullif(trim(v_item ->> 'note'), '');

    if v_relation_type not in ('main', 'spin_off', 'remake', 'remaster', 'dlc', 'expansion', 'other') then
      raise exception 'Tipo relazione non valido per %', v_key;
    end if;
    if coalesce(v_release_order, 0) <= 0 then
      raise exception 'Ordine di uscita non valido per %', v_key;
    end if;
    if v_narrative_order is not null and v_narrative_order <= 0 then
      raise exception 'Ordine narrativo non valido per %', v_key;
    end if;
    if not exists (select 1 from public.catalog_games where match_key = v_key) then
      raise exception 'Gioco non trovato nel catalogo: %', v_key;
    end if;

    insert into public.franchise_games(
      franchise_id,
      game_key,
      relation_type,
      release_order,
      narrative_order,
      note
    ) values (
      p_franchise_id,
      v_key,
      v_relation_type,
      v_release_order,
      v_narrative_order,
      v_note
    )
    on conflict (franchise_id, game_key) do update set
      relation_type = excluded.relation_type,
      release_order = excluded.release_order,
      narrative_order = excluded.narrative_order,
      note = excluded.note,
      updated_at = now();

    v_count := v_count + 1;
  end loop;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_games_batch_saved',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('count', v_count)
  );

  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_save_franchise_games_batch(uuid, jsonb) from public;
grant execute on function public.admin_save_franchise_games_batch(uuid, jsonb) to authenticated;

create or replace function public.catalog_personalized_recommendations(
  p_limit integer default 12
)
returns jsonb
language sql
stable
security definer
set search_path = ''
set statement_timeout = '15s'
as $$
with
params as (
  select
    (select auth.uid()) as user_id,
    greatest(4, least(coalesce(p_limit, 12), 24)) as item_limit
),
diary_minutes as materialized (
  select
    gde.game_key,
    sum(gde.minutes_played)::integer as minutes_played
  from public.game_diary_entries gde
  join params p on p.user_id = gde.user_id
  group by gde.game_key
),
library_signals as materialized (
  select
    coalesce(
      nullif(ul.data #>> '{game,match_key}', ''),
      nullif(ul.data #>> '{game,canonical_id}', ''),
      ul.game_key
    ) as ref_key,
    (
      case when coalesce(nullif(ul.data ->> 'favorite', '')::boolean, false) then 6 else 0 end
      + case
          when coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) >= 4
            then (coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) - 2) * 2
          when coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) between 1 and 2 then -4
          else 0
        end
      + case coalesce(ul.data ->> 'status', 'saved')
          when 'completed' then 6
          when 'replay' then 4
          when 'playing' then 3
          when 'paused' then 1
          when 'backlog' then 1
          when 'abandoned' then -7
          else 0.5
        end
      + least(
          4::numeric,
          ln(1 + greatest(0, coalesce(nullif(ul.data ->> 'steamPlaytimeMinutes', '')::numeric, 0)) / 60)
        )
    )::numeric as signal_weight,
    coalesce(nullif(ul.data ->> 'favorite', '')::boolean, false) as favorite,
    coalesce(nullif(ul.data ->> 'rating', '')::numeric, 0) as rating,
    coalesce(ul.data ->> 'status', 'saved') as status,
    greatest(0, coalesce(nullif(ul.data ->> 'steamPlaytimeMinutes', '')::integer, 0)) as playtime_minutes,
    'library'::text as source
  from public.user_library ul
  join params p on p.user_id = ul.user_id
),
progress_signals as materialized (
  select
    ugp.game_key as ref_key,
    (
      case ugp.status
        when 'completed' then 7
        when 'replay' then 5
        when 'playing' then 3
        when 'paused' then 1
        when 'backlog' then 1
        when 'abandoned' then -8
        else 0.5
      end
      + least(
          5::numeric,
          ln(
            1 + greatest(
              0,
              coalesce(ugp.manual_playtime_minutes, 0) + coalesce(dm.minutes_played, 0)
            )::numeric / 60
          )
        )
      + case when ugp.progress_percent >= 80 then 2 when ugp.progress_percent >= 40 then 1 else 0 end
    )::numeric as signal_weight,
    false as favorite,
    0::numeric as rating,
    ugp.status,
    greatest(0, coalesce(ugp.manual_playtime_minutes, 0) + coalesce(dm.minutes_played, 0)) as playtime_minutes,
    'progress'::text as source
  from public.user_game_progress ugp
  join params p on p.user_id = ugp.user_id
  left join diary_minutes dm on dm.game_key = ugp.game_key
),
review_signals as materialized (
  select
    gr.game_key as ref_key,
    case gr.rating
      when 5 then 8
      when 4 then 5
      when 3 then 1
      when 2 then -3
      else -6
    end::numeric as signal_weight,
    false as favorite,
    gr.rating::numeric as rating,
    'reviewed'::text as status,
    0::integer as playtime_minutes,
    'review'::text as source
  from public.game_reviews gr
  join params p on p.user_id = gr.user_id
),
list_signals as materialized (
  select
    unnest(ul.game_keys) as ref_key,
    case
      when lower(ul.name) ~ '(wishlist|desider|da giocare|backlog)' then 2.5
      else 1
    end::numeric as signal_weight,
    false as favorite,
    0::numeric as rating,
    'listed'::text as status,
    0::integer as playtime_minutes,
    'list'::text as source
  from public.user_lists ul
  join params p on p.user_id = ul.user_id
),
raw_signals as materialized (
  select * from library_signals
  union all
  select * from progress_signals
  union all
  select * from review_signals
  union all
  select * from list_signals
),
resolved_signals as materialized (
  select
    cg.match_key,
    cg.title,
    sum(rs.signal_weight)::numeric as affinity,
    bool_or(rs.favorite) as favorite,
    max(rs.rating)::numeric as rating,
    max(rs.playtime_minutes)::integer as playtime_minutes,
    array_agg(distinct rs.status) as statuses,
    array_agg(distinct rs.source) as sources
  from raw_signals rs
  join lateral (
    select candidate.match_key, candidate.title
    from public.catalog_games candidate
    where candidate.match_key = rs.ref_key
       or candidate.canonical_id = rs.ref_key
    order by case when candidate.match_key = rs.ref_key then 0 else 1 end
    limit 1
  ) cg on true
  group by cg.match_key, cg.title
),
positive_games as materialized (
  select * from resolved_signals where affinity > 1
),
negative_games as materialized (
  select * from resolved_signals where affinity < 0
),
top_genres as materialized (
  select genre, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  cross join lateral unnest(cg.genres) as genre
  where nullif(trim(genre), '') is not null
  group by genre
  order by weight desc, genre
  limit 8
),
negative_genres as materialized (
  select genre, round(sum(abs(ng.affinity)), 2) as weight
  from negative_games ng
  join public.catalog_games cg on cg.match_key = ng.match_key
  cross join lateral unnest(cg.genres) as genre
  where nullif(trim(genre), '') is not null
  group by genre
  order by weight desc, genre
  limit 8
),
top_developers as materialized (
  select cg.developer, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  where nullif(trim(cg.developer), '') is not null
  group by cg.developer
  order by weight desc, cg.developer
  limit 6
),
negative_developers as materialized (
  select cg.developer, round(sum(abs(ng.affinity)), 2) as weight
  from negative_games ng
  join public.catalog_games cg on cg.match_key = ng.match_key
  where nullif(trim(cg.developer), '') is not null
  group by cg.developer
  order by weight desc, cg.developer
  limit 4
),
top_publishers as materialized (
  select cg.publisher, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  where nullif(trim(cg.publisher), '') is not null
  group by cg.publisher
  order by weight desc, cg.publisher
  limit 4
),
top_segments as materialized (
  select cg.market_segment, round(sum(pg.affinity), 2) as weight
  from positive_games pg
  join public.catalog_games cg on cg.match_key = pg.match_key
  where cg.market_segment in ('aaa', 'indie')
  group by cg.market_segment
  order by weight desc, cg.market_segment
  limit 2
),
other_positive as materialized (
  select
    gr.user_id,
    gr.game_key as ref_key,
    greatest(1, gr.rating - 3)::numeric as weight
  from public.game_reviews gr
  join params p on gr.user_id <> p.user_id
  where gr.rating >= 4
    and public.can_view_user_content(gr.user_id, 'activity')

  union all

  select
    gde.user_id,
    gde.game_key as ref_key,
    least(3::numeric, 1 + sum(gde.minutes_played)::numeric / 600) as weight
  from public.game_diary_entries gde
  join params p on gde.user_id <> p.user_id
  where gde.visibility = 'public'
    and public.can_view_user_content(gde.user_id, 'activity')
    and (gde.progress_percent >= 50 or gde.minutes_played >= 120)
  group by gde.user_id, gde.game_key
),
similar_users as materialized (
  select
    op.user_id,
    count(distinct op.ref_key)::integer as overlap_count,
    round(sum(least(pg.affinity, 10) * op.weight), 2) as similarity
  from other_positive op
  join positive_games pg on pg.match_key = op.ref_key
  group by op.user_id
  order by similarity desc, overlap_count desc, op.user_id
  limit 30
),
collaborative_raw as materialized (
  select
    op.ref_key,
    round(sum(su.similarity * op.weight), 2) as collaborative_score,
    count(distinct op.user_id)::integer as similar_user_count
  from similar_users su
  join other_positive op on op.user_id = su.user_id
  where not exists (
    select 1 from resolved_signals own where own.match_key = op.ref_key
  )
  group by op.ref_key
  order by collaborative_score desc, similar_user_count desc, op.ref_key
  limit 250
),
collaborative_candidates as materialized (
  select
    cg.match_key,
    max(cr.collaborative_score) as collaborative_score,
    max(cr.similar_user_count) as similar_user_count
  from collaborative_raw cr
  join lateral (
    select candidate.match_key
    from public.catalog_games candidate
    where candidate.match_key = cr.ref_key
       or candidate.canonical_id = cr.ref_key
    order by case when candidate.match_key = cr.ref_key then 0 else 1 end
    limit 1
  ) cg on true
  where not exists (select 1 from resolved_signals own where own.match_key = cg.match_key)
  group by cg.match_key
),
metadata_candidates as materialized (
  select cg.match_key
  from public.catalog_games cg
  where cg.category_group = 'base_game'
    and cg.image_url is not null
    and not exists (select 1 from resolved_signals own where own.match_key = cg.match_key)
    and (
      exists (select 1 from top_genres tg where tg.genre = any(cg.genres))
      or exists (select 1 from top_developers td where lower(td.developer) = lower(cg.developer))
      or exists (select 1 from top_publishers tp where lower(tp.publisher) = lower(cg.publisher))
    )
  order by cg.release_date desc nulls last, cg.match_key
  limit 800
),
candidate_keys as materialized (
  select match_key from metadata_candidates
  union
  select match_key from collaborative_candidates
),
scored_candidates as materialized (
  select
    cg.*,
    coalesce(genre_fit.score, 0) as genre_score,
    coalesce(developer_fit.score, 0) as developer_score,
    coalesce(publisher_fit.score, 0) as publisher_score,
    coalesce(segment_fit.score, 0) as segment_score,
    coalesce(negative_genre_fit.score, 0) as negative_genre_score,
    coalesce(negative_developer_fit.score, 0) as negative_developer_score,
    coalesce(cc.collaborative_score, 0) as collaborative_score,
    coalesce(cc.similar_user_count, 0) as similar_user_count,
    coalesce(community.average_rating, 0) as community_rating,
    coalesce(community.review_count, 0) as community_review_count,
    seed_matches.seed_titles,
    shared_genre.genre as primary_shared_genre,
    (
      coalesce(genre_fit.score, 0) * 1.4
      + coalesce(developer_fit.score, 0) * 2.2
      + coalesce(publisher_fit.score, 0) * 0.9
      + least(8, coalesce(segment_fit.score, 0) * 0.35)
      + least(35, coalesce(cc.collaborative_score, 0) * 0.04)
      + case
          when coalesce(community.review_count, 0) > 0
            then coalesce(community.average_rating, 0) * ln(1 + community.review_count) * 0.55
          else 0
        end
      + case
          when cg.release_year >= extract(year from current_date)::integer - 2 then 2
          when cg.release_year >= extract(year from current_date)::integer - 5 then 1
          else 0
        end
      - coalesce(negative_genre_fit.score, 0) * 1.6
      - coalesce(negative_developer_fit.score, 0) * 2.2
    )::numeric as recommendation_score
  from candidate_keys ck
  join public.catalog_games cg on cg.match_key = ck.match_key
  left join collaborative_candidates cc on cc.match_key = cg.match_key
  left join lateral (
    select round(sum(tg.weight), 2) as score
    from top_genres tg
    where tg.genre = any(cg.genres)
  ) genre_fit on true
  left join lateral (
    select round(sum(td.weight), 2) as score
    from top_developers td
    where lower(td.developer) = lower(cg.developer)
  ) developer_fit on true
  left join lateral (
    select round(sum(tp.weight), 2) as score
    from top_publishers tp
    where lower(tp.publisher) = lower(cg.publisher)
  ) publisher_fit on true
  left join lateral (
    select round(sum(ts.weight), 2) as score
    from top_segments ts
    where ts.market_segment = cg.market_segment
  ) segment_fit on true
  left join lateral (
    select round(sum(ng.weight), 2) as score
    from negative_genres ng
    where ng.genre = any(cg.genres)
  ) negative_genre_fit on true
  left join lateral (
    select round(sum(nd.weight), 2) as score
    from negative_developers nd
    where lower(nd.developer) = lower(cg.developer)
  ) negative_developer_fit on true
  left join lateral (
    select
      round(avg(gr.rating)::numeric, 2) as average_rating,
      count(*)::integer as review_count
    from public.game_reviews gr
    where gr.game_key in (cg.match_key, cg.canonical_id)
      and public.can_view_user_content(gr.user_id, 'activity')
  ) community on true
  left join lateral (
    select array_agg(seed.title order by seed.affinity desc, seed.title) as seed_titles
    from (
      select pg.title, pg.affinity
      from positive_games pg
      join public.catalog_games source_game on source_game.match_key = pg.match_key
      where
        (nullif(source_game.developer, '') is not null and lower(source_game.developer) = lower(cg.developer))
        or source_game.genres && cg.genres
      order by pg.affinity desc, pg.title
      limit 2
    ) seed
  ) seed_matches on true
  left join lateral (
    select tg.genre
    from top_genres tg
    where tg.genre = any(cg.genres)
    order by tg.weight desc, tg.genre
    limit 1
  ) shared_genre on true
),
ranked as materialized (
  select *
  from scored_candidates
  where recommendation_score > 0
  order by recommendation_score desc, community_rating desc, release_date desc nulls last, match_key
  limit (select item_limit from params)
),
recommendation_items as (
  select coalesce(jsonb_agg(
    public.catalog_game_card_json(cg)
    || jsonb_build_object(
      'recommendation_score', round(r.recommendation_score, 2),
      'recommendation_confidence', least(99, greatest(1, round(45 + r.recommendation_score * 1.4)))::integer,
      'similar_user_count', r.similar_user_count,
      'reasons', to_jsonb(array_remove(array[
        case
          when cardinality(r.seed_titles) = 1 then 'Perché hai apprezzato ' || r.seed_titles[1]
          when cardinality(r.seed_titles) >= 2 then 'Perché hai apprezzato ' || r.seed_titles[1] || ' e ' || r.seed_titles[2]
          else null
        end,
        case
          when r.similar_user_count >= 2 then 'Apprezzato da utenti con gusti simili ai tuoi'
          else null
        end,
        case
          when r.primary_shared_genre is not null then 'In linea con il tuo interesse per ' || r.primary_shared_genre
          else null
        end,
        case
          when r.developer_score > 0 and nullif(r.developer, '') is not null then 'Altro titolo di ' || r.developer
          else null
        end
      ]::text[], null))
    )
    order by r.recommendation_score desc, r.community_rating desc, cg.release_date desc nulls last, cg.match_key
  ), '[]'::jsonb) as items
  from ranked r
  join public.catalog_games cg on cg.match_key = r.match_key
),
profile_summary as (
  select jsonb_build_object(
    'positive_signals', (select count(*) from positive_games),
    'negative_signals', (select count(*) from negative_games),
    'similar_users', (select count(*) from similar_users),
    'top_genres', coalesce((
      select jsonb_agg(jsonb_build_object('name', tg.genre, 'weight', tg.weight) order by tg.weight desc, tg.genre)
      from top_genres tg
    ), '[]'::jsonb),
    'top_developers', coalesce((
      select jsonb_agg(jsonb_build_object('name', td.developer, 'weight', td.weight) order by td.weight desc, td.developer)
      from top_developers td
    ), '[]'::jsonb)
  ) as value
)
select jsonb_build_object(
  'mode', case
    when (select user_id from params) is null then 'signed_out'
    when (select count(*) from positive_games) = 0 then 'cold_start'
    else 'personalized'
  end,
  'generated_at', now(),
  'profile', (select value from profile_summary),
  'items', (select items from recommendation_items)
);
$$;

revoke all on function public.catalog_personalized_recommendations(integer) from public;
grant execute on function public.catalog_personalized_recommendations(integer) to authenticated;

comment on function public.catalog_personalized_recommendations(integer) is
'Ranking personale senza nuove tabelle: combina libreria, preferiti, voti, progressi, diario, liste, metadati e segnali aggregati di utenti simili.';
