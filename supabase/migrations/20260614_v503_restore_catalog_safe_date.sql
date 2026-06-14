-- The Free Vault v5.0.3
-- Ripristina la dipendenza catalog_safe_date usata dagli upsert set-based e IGDB.
-- Alcuni database self-hosted migrati da dump Cloud possono avere le RPC di
-- catalogo senza questo helper storico della v4.1.4.

begin;

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

comment on function public.catalog_safe_date(text) is
'Converte in modo sicuro una data ISO YYYY-MM-DD; restituisce NULL per valori assenti o non validi.';

commit;

notify pgrst, 'reload schema';
