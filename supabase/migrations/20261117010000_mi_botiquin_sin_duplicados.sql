-- Si el mismo usuario abre la app en dos lugares a la vez (por ejemplo el link del email en dos navegadores),
-- dos llamadas a mi_botiquin() podían crear dos botiquines. Un lock por usuario lo evita.
create or replace function public.mi_botiquin() returns setof public.botiquines
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  nuevo uuid;
begin
  if uid is null then raise exception 'sin sesion' using errcode = '28000'; end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));
  if not exists (select 1 from public.miembros where user_id = uid) then
    insert into public.botiquines (creado_por) values (uid) returning id into nuevo;
    insert into public.miembros (botiquin_id, user_id, rol, email)
      values (nuevo, uid, 'dueno', auth.jwt() ->> 'email');
  end if;
  return query
    select b.* from public.botiquines b
    join public.miembros m on m.botiquin_id = b.id and m.user_id = uid
    order by m.created_at;
end;
$$;
