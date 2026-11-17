-- Familia: al unirse a un botiquín con una invitación, si la persona tenía un botiquín propio
-- vacío (creado automáticamente al entrar por primera vez), se borra para que no quede un segundo
-- botiquín sin uso. Solo se borra si es la única miembro y no tiene medicamentos, compras ni consultas.
create or replace function public.unirse(codigo text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  inv public.invitaciones;
  uid uuid := auth.uid();
begin
  if uid is null then raise exception 'sin sesion' using errcode = '28000'; end if;
  select * into inv from public.invitaciones i
    where i.codigo = upper(trim(unirse.codigo)) and i.expira > now();
  if not found then raise exception 'codigo invalido o vencido' using errcode = 'P0002'; end if;

  insert into public.miembros (botiquin_id, user_id, email)
    values (inv.botiquin_id, uid, auth.jwt() ->> 'email')
    on conflict do nothing;

  delete from public.botiquines b
  where b.creado_por = uid
    and b.id <> inv.botiquin_id
    and not exists (select 1 from public.miembros m where m.botiquin_id = b.id and m.user_id <> uid)
    and not exists (select 1 from public.medicamentos x where x.botiquin_id = b.id)
    and not exists (select 1 from public.compras x where x.botiquin_id = b.id)
    and not exists (select 1 from public.consultas x where x.botiquin_id = b.id);

  return inv.botiquin_id;
end;
$$;

-- Ver quién comparte el botiquín con nombre (no solo email).
alter table public.miembros add column if not exists nombre text;

-- Guardar el nombre al crear la membresía (desde el perfil de Google, si existe).
create or replace function public.completar_miembro() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.nombre is null then
    new.nombre := coalesce(auth.jwt() -> 'user_metadata' ->> 'full_name', auth.jwt() -> 'user_metadata' ->> 'name');
  end if;
  return new;
end;
$$;
drop trigger if exists miembros_nombre on public.miembros;
create trigger miembros_nombre before insert on public.miembros
  for each row execute function public.completar_miembro();

-- Completar el nombre de las membresías que ya existen (desde el perfil de Google).
update public.miembros m
set nombre = coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name')
from auth.users u
where u.id = m.user_id and m.nombre is null;
