-- The Free Vault v5.1 — editor massivo delle saghe.
-- Aggiunge la rimozione batch; il salvataggio batch usa la RPC v4.7 esistente.

create or replace function public.admin_remove_franchise_games_batch(
  p_franchise_id uuid,
  p_game_keys jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_removed integer := 0;
begin
  if not public.is_admin() then
    raise exception 'Accesso amministratore richiesto' using errcode = '42501';
  end if;

  if not exists (select 1 from public.franchises where id = p_franchise_id) then
    raise exception 'Franchise non trovato';
  end if;

  if p_game_keys is null or jsonb_typeof(p_game_keys) <> 'array' or jsonb_array_length(p_game_keys) = 0 then
    raise exception 'Seleziona almeno un gioco';
  end if;

  if jsonb_array_length(p_game_keys) > 250 then
    raise exception 'Puoi rimuovere al massimo 250 giochi per volta';
  end if;

  delete from public.franchise_games fg
  where fg.franchise_id = p_franchise_id
    and fg.game_key in (
      select trim(value)
      from jsonb_array_elements_text(p_game_keys)
      where trim(value) <> ''
    );

  get diagnostics v_removed = row_count;

  insert into public.admin_audit_log(actor_id, action, target_type, target_id, metadata)
  values (
    v_user,
    'franchise_games_batch_removed',
    'franchise',
    p_franchise_id::text,
    jsonb_build_object('count', v_removed, 'game_keys', p_game_keys)
  );

  return public.admin_get_franchise(p_franchise_id);
end;
$$;

revoke all on function public.admin_remove_franchise_games_batch(uuid, jsonb) from public;
grant execute on function public.admin_remove_franchise_games_batch(uuid, jsonb) to authenticated;

notify pgrst, 'reload schema';
