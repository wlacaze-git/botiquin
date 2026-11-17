-- Botiquín: esquema inicial
-- Modelo: un usuario pertenece a uno o más "botiquines" (la casa). Todo cuelga del botiquín,
-- así se puede compartir con otras personas sin migrar datos.
-- La seguridad la da Row Level Security: la clave anon que va en la página no permite ver
-- nada que no sea de un botiquín del que el usuario es miembro.

-- ---------------------------------------------------------------- tablas

create table public.botiquines (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null default 'Mi casa' check (char_length(nombre) between 1 and 80),
  direccion   text not null default '' check (char_length(direccion) <= 200),
  creado_por  uuid not null references auth.users on delete cascade,
  created_at  timestamptz not null default now()
);

create table public.miembros (
  botiquin_id uuid not null references public.botiquines on delete cascade,
  user_id     uuid not null references auth.users on delete cascade,
  rol         text not null default 'miembro' check (rol in ('dueno', 'miembro')),
  email       text,
  created_at  timestamptz not null default now(),
  primary key (botiquin_id, user_id)
);
create index miembros_user_idx on public.miembros (user_id);

create table public.medicamentos (
  id           uuid primary key default gen_random_uuid(),
  botiquin_id  uuid not null references public.botiquines on delete cascade,
  nombre       text not null check (char_length(nombre) between 1 and 200),
  principio    text not null default '' check (char_length(principio) <= 300),
  presentacion text not null default '' check (char_length(presentacion) <= 200),
  cantidad     text not null default '' check (char_length(cantidad) <= 100),
  vencimiento  text not null default '' check (vencimiento ~ '^([0-9]{4}-[0-9]{2}(-[0-9]{2})?)?$'),
  uso          text not null default '' check (char_length(uso) <= 1000),
  receta       boolean not null default false,
  agregado     date not null default current_date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index medicamentos_botiquin_idx on public.medicamentos (botiquin_id);

-- Las consultas son privadas de quien las hizo, aunque el botiquín sea compartido.
create table public.consultas (
  id          uuid primary key default gen_random_uuid(),
  botiquin_id uuid not null references public.botiquines on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  fecha       timestamptz not null default now(),
  sintoma     text not null check (char_length(sintoma) <= 4000),
  con_foto    boolean not null default false,
  respuesta   text not null default '',
  compras     text[] not null default '{}'
);
create index consultas_user_fecha_idx on public.consultas (user_id, fecha desc);

create table public.compras (
  id          uuid primary key default gen_random_uuid(),
  botiquin_id uuid not null references public.botiquines on delete cascade,
  nombre      text not null check (char_length(nombre) between 1 and 200),
  motivo      text not null default '' check (char_length(motivo) <= 200),
  created_at  timestamptz not null default now()
);
create unique index compras_unica_idx on public.compras (botiquin_id, lower(nombre));

create table public.invitaciones (
  codigo      text primary key,
  botiquin_id uuid not null references public.botiquines on delete cascade,
  creado_por  uuid not null references auth.users on delete cascade,
  expira      timestamptz not null default now() + interval '7 days'
);

-- Cuántas llamadas a Claude hizo cada usuario por día (límite de gasto).
create table public.uso_claude (
  user_id uuid not null references auth.users on delete cascade,
  dia     date not null,
  n       int  not null default 0,
  primary key (user_id, dia)
);

-- ---------------------------------------------------------------- helpers

create function public.es_miembro(b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.miembros m where m.botiquin_id = b and m.user_id = auth.uid()
  );
$$;

create function public.tocar_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger medicamentos_updated_at before update on public.medicamentos
  for each row execute function public.tocar_updated_at();

-- ---------------------------------------------------------------- RLS

alter table public.botiquines   enable row level security;
alter table public.miembros     enable row level security;
alter table public.medicamentos enable row level security;
alter table public.consultas    enable row level security;
alter table public.compras      enable row level security;
alter table public.invitaciones enable row level security;
alter table public.uso_claude   enable row level security;  -- sin políticas: solo vía funciones

-- botiquines: se crean con mi_botiquin(); los miembros los ven y editan (nombre, dirección).
create policy "ver mis botiquines" on public.botiquines
  for select to authenticated using (public.es_miembro(id));
create policy "editar mis botiquines" on public.botiquines
  for update to authenticated using (public.es_miembro(id)) with check (public.es_miembro(id));

-- miembros: ver quién comparte el botiquín; salir de uno (borrar la propia fila).
create policy "ver miembros" on public.miembros
  for select to authenticated using (public.es_miembro(botiquin_id));
create policy "salir del botiquin" on public.miembros
  for delete to authenticated using (user_id = (select auth.uid()));

create policy "medicamentos del botiquin" on public.medicamentos
  for all to authenticated
  using (public.es_miembro(botiquin_id)) with check (public.es_miembro(botiquin_id));

create policy "compras del botiquin" on public.compras
  for all to authenticated
  using (public.es_miembro(botiquin_id)) with check (public.es_miembro(botiquin_id));

create policy "mis consultas" on public.consultas
  for all to authenticated
  using (user_id = (select auth.uid()) and public.es_miembro(botiquin_id))
  with check (user_id = (select auth.uid()) and public.es_miembro(botiquin_id));

-- invitaciones: solo se manejan con las funciones de abajo.

-- ---------------------------------------------------------------- funciones (RPC)

-- Devuelve los botiquines del usuario; si no tiene ninguno, le crea uno.
create function public.mi_botiquin() returns setof public.botiquines
language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  nuevo uuid;
begin
  if uid is null then raise exception 'sin sesion' using errcode = '28000'; end if;
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

-- Crea un código de invitación (válido 7 días) para un botiquín del que soy miembro.
create function public.crear_invitacion(b uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  c text;
begin
  if not public.es_miembro(b) then raise exception 'no sos miembro' using errcode = '42501'; end if;
  delete from public.invitaciones where expira < now();
  c := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.invitaciones (codigo, botiquin_id, creado_por) values (c, b, auth.uid());
  return c;
end;
$$;

-- Usa un código de invitación: me agrega como miembro y devuelve el id del botiquín.
create function public.unirse(codigo text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  inv public.invitaciones;
begin
  if auth.uid() is null then raise exception 'sin sesion' using errcode = '28000'; end if;
  select * into inv from public.invitaciones i
    where i.codigo = upper(trim(unirse.codigo)) and i.expira > now();
  if not found then raise exception 'codigo invalido o vencido' using errcode = 'P0002'; end if;
  insert into public.miembros (botiquin_id, user_id, email)
    values (inv.botiquin_id, auth.uid(), auth.jwt() ->> 'email')
    on conflict do nothing;
  return inv.botiquin_id;
end;
$$;

-- Suma una llamada a Claude al día de hoy y dice si todavía está dentro del límite.
create function public.consumir_cuota(limite int) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  total int;
begin
  if auth.uid() is null then return false; end if;
  insert into public.uso_claude (user_id, dia, n)
    values (auth.uid(), (now() at time zone 'Europe/Madrid')::date, 1)
    on conflict (user_id, dia) do update set n = public.uso_claude.n + 1
    returning n into total;
  return total <= limite;
end;
$$;

revoke execute on function public.mi_botiquin()          from public, anon;
revoke execute on function public.crear_invitacion(uuid) from public, anon;
revoke execute on function public.unirse(text)           from public, anon;
revoke execute on function public.consumir_cuota(int)    from public, anon;
revoke execute on function public.es_miembro(uuid)       from public, anon;
grant  execute on function public.mi_botiquin()          to authenticated;
grant  execute on function public.crear_invitacion(uuid) to authenticated;
grant  execute on function public.unirse(text)           to authenticated;
grant  execute on function public.consumir_cuota(int)    to authenticated;
grant  execute on function public.es_miembro(uuid)       to authenticated;

-- ---------------------------------------------------------------- realtime
-- Para que otro teléfono vea los cambios al instante (Realtime respeta RLS).
alter publication supabase_realtime add table public.medicamentos, public.compras;
