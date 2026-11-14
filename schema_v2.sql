-- =====================================================================
-- SimNeuro · Esquema v2 (acceso como en el simulador de innovación)
-- Ejecutar UNA VEZ en: Supabase → SQL Editor → New query → Run
--
-- Acceso:
--  * Equipos: los estudiantes registran su equipo (nombre, producto, contraseña,
--    alias de integrantes). Luego ingresan con código de clase + nombre del equipo
--    + contraseña, y eligen quién son dentro del equipo.
--  * Docente: correo + contraseña (contraseña temporal que se cambia al entrar),
--    con pregunta de seguridad para recuperarla.
--  * Contraseñas con bcrypt; bloqueo de 15 min tras 5 intentos fallidos;
--    sesiones con token aleatorio (solo se guarda su hash).
--  * No se guardan nombres reales: solo alias.
--
-- Seguridad de datos: tablas con RLS activado y SIN políticas; el navegador
-- solo puede llamar a las funciones públicas (RPC) de la sección final.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto schema extensions;

-- ---------- Limpieza de la versión 1 (si existía) ----------
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='sn_clases' and column_name='cod_est_hash') then
    drop function if exists public.sn_clase_est(text);
    drop function if exists public.sn_clase_doc(text);
    drop function if exists public.sn_crear_clase(text,text,text);
    drop function if exists public.sn_enviar_obs(text,text,text,int,int,int,text,int,int,int,int,text);
    drop function if exists public.sn_enviar_sim(text,text,text,int,int,jsonb);
    drop function if exists public.sn_enviar_nota(text,text,int,text);
    drop function if exists public.sn_resumen(text);
    drop function if exists public.sn_docente(text);
    drop function if exists public.sn_docente_borrar(text,bigint);
    drop table if exists public.sn_fallos, public.sn_notas, public.sn_sims, public.sn_obs, public.sn_clases cascade;
  end if;
end $$;

-- ---------- Tablas ----------
create table if not exists public.sn_clases (
  id               uuid primary key default gen_random_uuid(),
  nombre           text not null,
  cod_hash         text not null,
  registro_abierto boolean not null default true,
  activa           boolean not null default true,
  creada           timestamptz not null default now()
);

create table if not exists public.sn_docentes (
  id             uuid primary key default gen_random_uuid(),
  nombre         text not null,
  email          text not null,
  clave_hash     text not null,
  clave_temporal boolean not null default true,
  pregunta       text not null default '',
  resp_hash      text not null default '',
  activo         boolean not null default true,
  creado         timestamptz not null default now()
);
create unique index if not exists sn_docentes_email_uq on public.sn_docentes (lower(email));

create table if not exists public.sn_equipos (
  id             uuid primary key default gen_random_uuid(),
  clase_id       uuid not null references public.sn_clases(id) on delete cascade,
  nombre         text not null check (char_length(nombre) between 3 and 40),
  producto       smallint not null check (producto between 1 and 3),
  clave_hash     text not null,
  clave_temporal boolean not null default false,
  creado         timestamptz not null default now()
);
create unique index if not exists sn_equipos_nombre_uq on public.sn_equipos (clase_id, lower(nombre));

create table if not exists public.sn_integrantes (
  id        uuid primary key default gen_random_uuid(),
  equipo_id uuid not null references public.sn_equipos(id) on delete cascade,
  alias     text not null check (char_length(alias) between 2 and 24),
  creado    timestamptz not null default now()
);
create unique index if not exists sn_integrantes_alias_uq on public.sn_integrantes (equipo_id, lower(alias));

create table if not exists public.sn_sesiones (
  token_hash    text primary key,
  rol           text not null check (rol in ('equipo','docente')),
  clase_id      uuid,
  equipo_id     uuid references public.sn_equipos(id) on delete cascade,
  integrante_id uuid references public.sn_integrantes(id) on delete cascade,
  docente_id    uuid references public.sn_docentes(id) on delete cascade,
  tmp           boolean not null default false,
  vence         timestamptz not null
);

create table if not exists public.sn_intentos (
  clave text not null,
  fecha timestamptz not null default now(),
  ok    boolean not null
);
create index if not exists sn_intentos_ix on public.sn_intentos (clave, fecha);

create table if not exists public.sn_obs (
  id            bigint generated always as identity primary key,
  clase_id      uuid not null references public.sn_clases(id) on delete cascade,
  equipo_id     uuid not null references public.sn_equipos(id) on delete cascade,
  integrante_id uuid references public.sn_integrantes(id) on delete set null,
  investigador  text not null check (char_length(investigador) between 1 and 24),
  cid           text not null check (char_length(cid) between 8 and 64),
  producto      smallint not null check (producto between 1 and 3),
  part_producto smallint check (part_producto between 1 and 3),
  orden         text not null check (orden in ('DR','RD')),
  q_d smallint not null check (q_d between 1 and 10),
  g_d smallint not null check (g_d between 1 and 10),
  q_r smallint not null check (q_r between 1 and 10),
  g_r smallint not null check (g_r between 1 and 10),
  eleccion      text not null check (eleccion in ('d','r')),
  creada        timestamptz not null default now(),
  unique (clase_id, cid)
);

create table if not exists public.sn_sims (
  id            bigint generated always as identity primary key,
  clase_id      uuid not null references public.sn_clases(id) on delete cascade,
  equipo_id     uuid not null references public.sn_equipos(id) on delete cascade,
  integrante_id uuid references public.sn_integrantes(id) on delete set null,
  investigador  text not null check (char_length(investigador) between 1 and 24),
  cid           text not null check (char_length(cid) between 8 and 64),
  producto      smallint not null check (producto between 1 and 3),
  datos         jsonb not null check (pg_column_size(datos) < 4000),
  creada        timestamptz not null default now(),
  unique (clase_id, cid)
);

create table if not exists public.sn_notas (
  integrante_id uuid primary key references public.sn_integrantes(id) on delete cascade,
  clase_id      uuid not null references public.sn_clases(id) on delete cascade,
  equipo_id     uuid not null references public.sn_equipos(id) on delete cascade,
  investigador  text not null,
  nota          text not null check (char_length(nota) <= 1200),
  actualizada   timestamptz not null default now()
);

-- ---------- RLS: activado, sin políticas, sin permisos directos ----------
alter table public.sn_clases      enable row level security;
alter table public.sn_docentes    enable row level security;
alter table public.sn_equipos     enable row level security;
alter table public.sn_integrantes enable row level security;
alter table public.sn_sesiones    enable row level security;
alter table public.sn_intentos    enable row level security;
alter table public.sn_obs         enable row level security;
alter table public.sn_sims        enable row level security;
alter table public.sn_notas       enable row level security;

revoke all on public.sn_clases, public.sn_docentes, public.sn_equipos, public.sn_integrantes,
  public.sn_sesiones, public.sn_intentos, public.sn_obs, public.sn_sims, public.sn_notas
  from public, anon, authenticated;

-- ---------- Funciones internas ----------
create or replace function public.sn_th(p_token text) returns text
language sql immutable security definer set search_path = public, extensions as $$
  select encode(digest(coalesce(p_token,''), 'sha256'), 'hex')
$$;

create or replace function public.sn_bloqueado(p_clave text) returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select count(*) >= 5 from sn_intentos
   where clave = p_clave and not ok
     and fecha > now() - interval '15 minutes'
     and fecha > coalesce((select max(fecha) from sn_intentos where clave = p_clave and ok), '-infinity'::timestamptz)
$$;

create or replace function public.sn_intento(p_clave text, p_ok boolean) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into sn_intentos(clave, ok) values (p_clave, p_ok);
  if random() < 0.05 then delete from sn_intentos where fecha < now() - interval '1 day'; end if;
end $$;

create or replace function public.sn_nueva_sesion(p_rol text, p_clase uuid, p_equipo uuid, p_integrante uuid, p_docente uuid, p_tmp boolean)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare t text;
begin
  t := encode(gen_random_bytes(24), 'hex');
  delete from sn_sesiones where vence < now();
  insert into sn_sesiones(token_hash, rol, clase_id, equipo_id, integrante_id, docente_id, tmp, vence)
  values (sn_th(t), p_rol, p_clase, p_equipo, p_integrante, p_docente, p_tmp, now() + interval '3 hours');
  return t;
end $$;

create or replace function public.sn_ses(p_token text, p_rol text) returns public.sn_sesiones
language sql stable security definer set search_path = public, extensions as $$
  select * from sn_sesiones where token_hash = sn_th(p_token) and rol = p_rol and vence > now()
$$;

-- Clase por código; protege contra adivinación masiva (60 fallos por minuto bloquean todo)
create or replace function public.sn_clase_por_codigo(p_codigo text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  if p_codigo is null or char_length(trim(p_codigo)) < 6 or char_length(p_codigo) > 64 then return null; end if;
  if (select count(*) from sn_intentos where clave = 'cod|global' and not ok and fecha > now() - interval '1 minute') >= 60 then
    return null;
  end if;
  select id into v from sn_clases where activa and cod_hash = crypt(upper(trim(p_codigo)), cod_hash) limit 1;
  if v is null then perform sn_intento('cod|global', false); end if;
  return v;
end $$;

create or replace function public.sn_equipo_json(p_equipo uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('id', e.id, 'nombre', e.nombre, 'producto', e.producto)
  from sn_equipos e where e.id = p_equipo
$$;

create or replace function public.sn_integrantes_json(p_equipo uuid) returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'alias', alias) order by alias), '[]'::jsonb)
  from sn_integrantes where equipo_id = p_equipo
$$;

-- Crear clase y docente: SOLO desde el SQL Editor (no accesibles desde el navegador)
create or replace function public.sn_crear_clase(p_nombre text, p_codigo text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  if char_length(coalesce(p_codigo,'')) < 8 then raise exception 'El código debe tener al menos 8 caracteres'; end if;
  insert into sn_clases(nombre, cod_hash) values (p_nombre, crypt(upper(trim(p_codigo)), gen_salt('bf'))) returning id into v;
  return v;
end $$;

create or replace function public.sn_crear_docente(p_nombre text, p_email text, p_clave_temporal text, p_pregunta text, p_respuesta text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  if char_length(coalesce(p_clave_temporal,'')) < 8 then raise exception 'La contraseña temporal debe tener al menos 8 caracteres'; end if;
  if char_length(coalesce(p_pregunta,'')) < 8 or char_length(coalesce(p_respuesta,'')) < 2 then
    raise exception 'Indica una pregunta de seguridad (mín. 8 caracteres) y su respuesta';
  end if;
  insert into sn_docentes(nombre, email, clave_hash, clave_temporal, pregunta, resp_hash)
  values (trim(p_nombre), lower(trim(p_email)), crypt(p_clave_temporal, gen_salt('bf')), true, trim(p_pregunta),
          crypt(lower(regexp_replace(trim(p_respuesta), '\s+', ' ', 'g')), gen_salt('bf')))
  returning id into v;
  return v;
end $$;

-- ---------- Funciones públicas (RPC) ----------
-- Verifica el código de clase (pantalla de ingreso/registro)
create or replace function public.sn_inicio(p_codigo text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v uuid; r record;
begin
  v := sn_clase_por_codigo(p_codigo);
  if v is null then return jsonb_build_object('ok', false, 'error', 'codigo'); end if;
  select nombre, registro_abierto into r from sn_clases where id = v;
  return jsonb_build_object('ok', true, 'clase', r.nombre, 'registro', r.registro_abierto);
end $$;

create or replace function public.sn_registrar_equipo(
  p_codigo text, p_nombre text, p_producto int, p_clave text, p_integrantes jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v uuid; ab boolean; nom text; eq uuid; a text; al text[] := '{}'; i int := 0; tok text;
begin
  v := sn_clase_por_codigo(p_codigo);
  if v is null then return jsonb_build_object('ok', false, 'error', 'codigo'); end if;
  select registro_abierto into ab from sn_clases where id = v;
  if not ab then return jsonb_build_object('ok', false, 'error', 'cerrado'); end if;
  nom := regexp_replace(trim(coalesce(p_nombre,'')), '\s+', ' ', 'g');
  if char_length(nom) < 3 or char_length(nom) > 40 then return jsonb_build_object('ok', false, 'error', 'nombre'); end if;
  if p_producto is null or p_producto not between 1 and 3 then return jsonb_build_object('ok', false, 'error', 'producto'); end if;
  if char_length(coalesce(p_clave,'')) < 4 or char_length(p_clave) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
  if jsonb_typeof(coalesce(p_integrantes,'null'::jsonb)) <> 'array' then return jsonb_build_object('ok', false, 'error', 'integrantes'); end if;
  for a in select jsonb_array_elements_text(p_integrantes) loop
    al := al || regexp_replace(trim(a), '\s+', ' ', 'g');
  end loop;
  if coalesce(array_length(al,1),0) < 1 or array_length(al,1) > 12 then return jsonb_build_object('ok', false, 'error', 'integrantes'); end if;
  foreach a in array al loop
    if char_length(a) < 2 or char_length(a) > 24 then return jsonb_build_object('ok', false, 'error', 'alias'); end if;
  end loop;
  if (select count(distinct lower(x)) from unnest(al) x) <> array_length(al,1) then
    return jsonb_build_object('ok', false, 'error', 'alias_repetido');
  end if;
  if (select count(*) from sn_equipos where clase_id = v) >= 30 then return jsonb_build_object('ok', false, 'error', 'limite'); end if;
  if exists (select 1 from sn_equipos where clase_id = v and lower(nombre) = lower(nom)) then
    return jsonb_build_object('ok', false, 'error', 'repetido');
  end if;
  insert into sn_equipos(clase_id, nombre, producto, clave_hash)
  values (v, nom, p_producto, crypt(p_clave, gen_salt('bf'))) returning id into eq;
  foreach a in array al loop insert into sn_integrantes(equipo_id, alias) values (eq, a); end loop;
  tok := sn_nueva_sesion('equipo', v, eq, null, null, false);
  return jsonb_build_object('ok', true, 'token', tok, 'tipo', 'equipo', 'equipo', sn_equipo_json(eq),
                            'integrantes', sn_integrantes_json(eq), 'cambiar_clave', false);
end $$;

create or replace function public.sn_login(p_usuario text, p_clave text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u text; d record; v uuid; e record; k text; tok text;
begin
  u := trim(coalesce(p_usuario,''));
  if u = '' or coalesce(p_clave,'') = '' then return jsonb_build_object('ok', false, 'error', 'vacio'); end if;
  if position('@' in u) > 0 then
    k := 'doc|' || lower(u);
    if sn_bloqueado(k) then return jsonb_build_object('ok', false, 'error', 'bloqueado'); end if;
    select * into d from sn_docentes where lower(email) = lower(u) and activo;
    if not found or d.clave_hash <> crypt(p_clave, d.clave_hash) then
      perform sn_intento(k, false);
      return jsonb_build_object('ok', false, 'error', 'datos');
    end if;
    perform sn_intento(k, true);
    tok := sn_nueva_sesion('docente', null, null, null, d.id, d.clave_temporal);
    return jsonb_build_object('ok', true, 'token', tok, 'tipo', 'docente', 'nombre', d.nombre, 'cambiar_clave', d.clave_temporal);
  end if;
  v := sn_clase_por_codigo(p_codigo);
  if v is null then return jsonb_build_object('ok', false, 'error', 'codigo'); end if;
  k := 'eq|' || v::text || '|' || lower(regexp_replace(u, '\s+', ' ', 'g'));
  if sn_bloqueado(k) then return jsonb_build_object('ok', false, 'error', 'bloqueado'); end if;
  select * into e from sn_equipos where clase_id = v and lower(nombre) = lower(regexp_replace(u, '\s+', ' ', 'g'));
  if not found or e.clave_hash <> crypt(p_clave, e.clave_hash) then
    perform sn_intento(k, false);
    return jsonb_build_object('ok', false, 'error', 'datos');
  end if;
  perform sn_intento(k, true);
  tok := sn_nueva_sesion('equipo', v, e.id, null, null, e.clave_temporal);
  return jsonb_build_object('ok', true, 'token', tok, 'tipo', 'equipo', 'equipo', sn_equipo_json(e.id),
                            'integrantes', sn_integrantes_json(e.id), 'cambiar_clave', e.clave_temporal);
end $$;

-- Estado de una sesión (para retomar tras recargar la página)
create or replace function public.sn_sesion_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; d record; i record;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is not null then
    select alias into i from sn_integrantes where id = s.integrante_id;
    return jsonb_build_object('ok', true, 'tipo', 'equipo', 'equipo', sn_equipo_json(s.equipo_id),
      'integrantes', sn_integrantes_json(s.equipo_id), 'integrante', s.integrante_id, 'alias', i.alias, 'cambiar_clave', s.tmp);
  end if;
  s := sn_ses(p_token, 'docente');
  if s.token_hash is not null then
    select nombre into d from sn_docentes where id = s.docente_id;
    return jsonb_build_object('ok', true, 'tipo', 'docente', 'nombre', d.nombre, 'cambiar_clave', s.tmp);
  end if;
  return jsonb_build_object('ok', false, 'error', 'sesion');
end $$;

create or replace function public.sn_elegir(p_token text, p_integrante uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; a text;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  select alias into a from sn_integrantes where id = p_integrante and equipo_id = s.equipo_id;
  if a is null then return jsonb_build_object('ok', false, 'error', 'integrante'); end if;
  update sn_sesiones set integrante_id = p_integrante where token_hash = s.token_hash;
  return jsonb_build_object('ok', true, 'integrante', p_integrante, 'alias', a);
end $$;

create or replace function public.sn_agregar_integrante(p_token text, p_alias text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; a text; nid uuid;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  a := regexp_replace(trim(coalesce(p_alias,'')), '\s+', ' ', 'g');
  if char_length(a) < 2 or char_length(a) > 24 then return jsonb_build_object('ok', false, 'error', 'alias'); end if;
  if (select count(*) from sn_integrantes where equipo_id = s.equipo_id) >= 12 then
    return jsonb_build_object('ok', false, 'error', 'limite');
  end if;
  if exists (select 1 from sn_integrantes where equipo_id = s.equipo_id and lower(alias) = lower(a)) then
    return jsonb_build_object('ok', false, 'error', 'alias_repetido');
  end if;
  insert into sn_integrantes(equipo_id, alias) values (s.equipo_id, a) returning id into nid;
  update sn_sesiones set integrante_id = nid where token_hash = s.token_hash;
  return jsonb_build_object('ok', true, 'integrante', nid, 'alias', a, 'integrantes', sn_integrantes_json(s.equipo_id));
end $$;

create or replace function public.sn_cambiar_clave(p_token text, p_actual text, p_nueva text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; e record; d record;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is not null then
    if char_length(coalesce(p_nueva,'')) < 4 or char_length(p_nueva) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
    select * into e from sn_equipos where id = s.equipo_id;
    if e.clave_hash <> crypt(coalesce(p_actual,''), e.clave_hash) then return jsonb_build_object('ok', false, 'error', 'actual'); end if;
    if p_actual = p_nueva then return jsonb_build_object('ok', false, 'error', 'igual'); end if;
    update sn_equipos set clave_hash = crypt(p_nueva, gen_salt('bf')), clave_temporal = false where id = e.id;
    update sn_sesiones set tmp = false where token_hash = s.token_hash;
    return jsonb_build_object('ok', true, 'integrantes', sn_integrantes_json(e.id));
  end if;
  s := sn_ses(p_token, 'docente');
  if s.token_hash is not null then
    if char_length(coalesce(p_nueva,'')) < 8 or char_length(p_nueva) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
    select * into d from sn_docentes where id = s.docente_id;
    if d.clave_hash <> crypt(coalesce(p_actual,''), d.clave_hash) then return jsonb_build_object('ok', false, 'error', 'actual'); end if;
    if p_actual = p_nueva then return jsonb_build_object('ok', false, 'error', 'igual'); end if;
    update sn_docentes set clave_hash = crypt(p_nueva, gen_salt('bf')), clave_temporal = false where id = d.id;
    update sn_sesiones set tmp = false where token_hash = s.token_hash;
    return jsonb_build_object('ok', true);
  end if;
  return jsonb_build_object('ok', false, 'error', 'sesion');
end $$;

create or replace function public.sn_salir(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from sn_sesiones where token_hash = sn_th(p_token);
  return jsonb_build_object('ok', true);
end $$;

-- Recuperación de la contraseña del docente
create or replace function public.sn_doc_pregunta(p_email text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare p text;
begin
  select pregunta into p from sn_docentes where lower(email) = lower(trim(coalesce(p_email,''))) and activo and resp_hash <> '';
  if p is null then return jsonb_build_object('ok', false, 'error', 'datos'); end if;
  return jsonb_build_object('ok', true, 'pregunta', p);
end $$;

create or replace function public.sn_doc_recuperar(p_email text, p_respuesta text, p_nueva text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d record; k text; r text;
begin
  k := 'rec|' || lower(trim(coalesce(p_email,'')));
  if sn_bloqueado(k) then return jsonb_build_object('ok', false, 'error', 'bloqueado'); end if;
  if char_length(coalesce(p_nueva,'')) < 8 or char_length(p_nueva) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
  r := lower(regexp_replace(trim(coalesce(p_respuesta,'')), '\s+', ' ', 'g'));
  select * into d from sn_docentes where lower(email) = lower(trim(coalesce(p_email,''))) and activo and resp_hash <> '';
  if not found or d.resp_hash <> crypt(r, d.resp_hash) then
    perform sn_intento(k, false);
    return jsonb_build_object('ok', false, 'error', 'datos');
  end if;
  perform sn_intento(k, true);
  update sn_docentes set clave_hash = crypt(p_nueva, gen_salt('bf')), clave_temporal = false where id = d.id;
  delete from sn_sesiones where docente_id = d.id;
  return jsonb_build_object('ok', true);
end $$;

-- ----- Datos del estudio (requieren sesión de equipo con integrante elegido) -----
create or replace function public.sn_enviar_obs(
  p_token text, p_cid text, p_part_producto int, p_orden text,
  p_qd int, p_gd int, p_qr int, p_gr int, p_eleccion text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; prod int; alias text;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp or s.integrante_id is null then return jsonb_build_object('ok', false, 'error', 'integrante'); end if;
  if (select count(*) from sn_obs where clase_id = s.clase_id) >= 5000 then return jsonb_build_object('ok', false, 'error', 'limite'); end if;
  select producto into prod from sn_equipos where id = s.equipo_id;
  select i.alias into alias from sn_integrantes i where i.id = s.integrante_id;
  begin
    insert into sn_obs(clase_id, equipo_id, integrante_id, investigador, cid, producto, part_producto, orden, q_d, g_d, q_r, g_r, eleccion)
    values (s.clase_id, s.equipo_id, s.integrante_id, alias, p_cid, prod, p_part_producto, p_orden, p_qd, p_gd, p_qr, p_gr, p_eleccion)
    on conflict (clase_id, cid) do nothing;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'datos');
  end;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sn_enviar_sim(p_token text, p_cid text, p_datos jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; prod int; alias text;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp or s.integrante_id is null then return jsonb_build_object('ok', false, 'error', 'integrante'); end if;
  if (select count(*) from sn_sims where clase_id = s.clase_id) >= 5000 then return jsonb_build_object('ok', false, 'error', 'limite'); end if;
  select producto into prod from sn_equipos where id = s.equipo_id;
  select i.alias into alias from sn_integrantes i where i.id = s.integrante_id;
  begin
    insert into sn_sims(clase_id, equipo_id, integrante_id, investigador, cid, producto, datos)
    values (s.clase_id, s.equipo_id, s.integrante_id, alias, p_cid, prod, p_datos)
    on conflict (clase_id, cid) do nothing;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'datos');
  end;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sn_enviar_nota(p_token text, p_nota text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; alias text;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp or s.integrante_id is null then return jsonb_build_object('ok', false, 'error', 'integrante'); end if;
  select i.alias into alias from sn_integrantes i where i.id = s.integrante_id;
  begin
    insert into sn_notas(integrante_id, clase_id, equipo_id, investigador, nota)
    values (s.integrante_id, s.clase_id, s.equipo_id, alias, left(coalesce(p_nota,''), 1200))
    on conflict (integrante_id) do update set nota = excluded.nota, actualizada = now();
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'datos');
  end;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sn_resumen(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; r jsonb;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  select coalesce(jsonb_agg(jsonb_build_array(producto, orden, q_d, g_d, q_r, g_r, eleccion) order by id), '[]'::jsonb)
    into r from sn_obs where clase_id = s.clase_id;
  return jsonb_build_object('ok', true, 'obs', r);
end $$;

-- ----- Panel docente -----
create or replace function public.sn_docente(p_token text, p_clase uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; v uuid; c record; o jsonb; si jsonb; n jsonb; eqs jsonb; cls jsonb;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre) order by creada desc), '[]'::jsonb) into cls from sn_clases;
  v := coalesce(p_clase, (select id from sn_clases where activa order by creada desc limit 1));
  select * into c from sn_clases where id = v;
  if not found then return jsonb_build_object('ok', true, 'clases', cls, 'clase', null); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'producto', e.producto, 'temporal', e.clave_temporal,
           'integrantes', sn_integrantes_json(e.id)) order by e.creado), '[]'::jsonb) into eqs from sn_equipos e where e.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'inv', b.investigador, 'eq', e.nombre, 'prod', b.producto, 'pe', b.part_producto,
           'orden', b.orden, 'qd', b.q_d, 'gd', b.g_d, 'qr', b.q_r, 'gr', b.g_r, 'el', b.eleccion, 't', b.creada) order by b.id), '[]'::jsonb)
    into o from sn_obs b join sn_equipos e on e.id = b.equipo_id where b.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('inv', m.investigador, 'eq', e.nombre, 'prod', m.producto, 'datos', m.datos, 't', m.creada) order by m.id), '[]'::jsonb)
    into si from sn_sims m join sn_equipos e on e.id = m.equipo_id where m.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('inv', t.investigador, 'eq', e.nombre, 'nota', t.nota, 't', t.actualizada) order by t.investigador), '[]'::jsonb)
    into n from sn_notas t join sn_equipos e on e.id = t.equipo_id where t.clase_id = v;
  return jsonb_build_object('ok', true, 'clases', cls, 'clase', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'registro', c.registro_abierto),
                            'equipos', eqs, 'obs', o, 'sims', si, 'notas', n);
end $$;

create or replace function public.sn_docente_borrar(p_token text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  delete from sn_obs where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- accion: 'reiniciar' (contraseña temporal nueva), 'borrar' (equipo y sus datos)
create or replace function public.sn_docente_equipo(p_token text, p_accion text, p_equipo uuid, p_valor text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  if p_accion = 'reiniciar' then
    if char_length(coalesce(p_valor,'')) < 4 or char_length(p_valor) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
    update sn_equipos set clave_hash = crypt(p_valor, gen_salt('bf')), clave_temporal = true where id = p_equipo;
    delete from sn_sesiones where equipo_id = p_equipo;
    delete from sn_intentos where clave = (select 'eq|' || clase_id::text || '|' || lower(nombre) from sn_equipos where id = p_equipo);
  elsif p_accion = 'borrar' then
    delete from sn_equipos where id = p_equipo;
  else
    return jsonb_build_object('ok', false, 'error', 'accion');
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sn_docente_config(p_token text, p_clase uuid, p_registro boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  update sn_clases set registro_abierto = coalesce(p_registro, registro_abierto) where id = p_clase;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Permisos de ejecución ----------
revoke all on function
  public.sn_th(text), public.sn_bloqueado(text), public.sn_intento(text,boolean),
  public.sn_nueva_sesion(text,uuid,uuid,uuid,uuid,boolean), public.sn_ses(text,text),
  public.sn_clase_por_codigo(text), public.sn_equipo_json(uuid), public.sn_integrantes_json(uuid),
  public.sn_crear_clase(text,text), public.sn_crear_docente(text,text,text,text,text)
  from public, anon, authenticated;

revoke all on function
  public.sn_inicio(text), public.sn_registrar_equipo(text,text,int,text,jsonb), public.sn_login(text,text,text),
  public.sn_sesion_info(text), public.sn_elegir(text,uuid), public.sn_agregar_integrante(text,text),
  public.sn_cambiar_clave(text,text,text), public.sn_salir(text), public.sn_doc_pregunta(text),
  public.sn_doc_recuperar(text,text,text), public.sn_enviar_obs(text,text,int,text,int,int,int,int,text),
  public.sn_enviar_sim(text,text,jsonb), public.sn_enviar_nota(text,text), public.sn_resumen(text),
  public.sn_docente(text,uuid), public.sn_docente_borrar(text,bigint),
  public.sn_docente_equipo(text,text,uuid,text), public.sn_docente_config(text,uuid,boolean)
  from public;

grant execute on function
  public.sn_inicio(text), public.sn_registrar_equipo(text,text,int,text,jsonb), public.sn_login(text,text,text),
  public.sn_sesion_info(text), public.sn_elegir(text,uuid), public.sn_agregar_integrante(text,text),
  public.sn_cambiar_clave(text,text,text), public.sn_salir(text), public.sn_doc_pregunta(text),
  public.sn_doc_recuperar(text,text,text), public.sn_enviar_obs(text,text,int,text,int,int,int,int,text),
  public.sn_enviar_sim(text,text,jsonb), public.sn_enviar_nota(text,text), public.sn_resumen(text),
  public.sn_docente(text,uuid), public.sn_docente_borrar(text,bigint),
  public.sn_docente_equipo(text,text,uuid,text), public.sn_docente_config(text,uuid,boolean)
  to anon, authenticated;

-- ====== Ajustes v3: sin bloqueo, claves de equipo visibles al docente, cuenta del docente ======

alter table public.sn_equipos add column if not exists clave_texto text not null default '';



-- Sin bloqueo por intentos fallidos (se mantiene una pausa de 0,4 s por intento fallido)

create or replace function public.sn_bloqueado(p_clave text) returns boolean

language sql stable security definer set search_path = public, extensions as $$ select false $$;



create or replace function public.sn_login(p_usuario text, p_clave text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare u text; d record; v uuid; e record; k text; tok text;
begin
  u := trim(coalesce(p_usuario,''));
  if u = '' or coalesce(p_clave,'') = '' then return jsonb_build_object('ok', false, 'error', 'vacio'); end if;
  if position('@' in u) > 0 then
    k := 'doc|' || lower(u);
    if sn_bloqueado(k) then return jsonb_build_object('ok', false, 'error', 'bloqueado'); end if;
    select * into d from sn_docentes where lower(email) = lower(u) and activo;
    if not found or d.clave_hash <> crypt(p_clave, d.clave_hash) then
      perform sn_intento(k, false); perform pg_sleep(0.4);
      return jsonb_build_object('ok', false, 'error', 'datos');
    end if;
    perform sn_intento(k, true);
    tok := sn_nueva_sesion('docente', null, null, null, d.id, d.clave_temporal);
    return jsonb_build_object('ok', true, 'token', tok, 'tipo', 'docente', 'nombre', d.nombre, 'cambiar_clave', d.clave_temporal);
  end if;
  v := sn_clase_por_codigo(p_codigo);
  if v is null then return jsonb_build_object('ok', false, 'error', 'codigo'); end if;
  k := 'eq|' || v::text || '|' || lower(regexp_replace(u, '\s+', ' ', 'g'));
  if sn_bloqueado(k) then return jsonb_build_object('ok', false, 'error', 'bloqueado'); end if;
  select * into e from sn_equipos where clase_id = v and lower(nombre) = lower(regexp_replace(u, '\s+', ' ', 'g'));
  if not found or e.clave_hash <> crypt(p_clave, e.clave_hash) then
    perform sn_intento(k, false); perform pg_sleep(0.4);
    return jsonb_build_object('ok', false, 'error', 'datos');
  end if;
  perform sn_intento(k, true);
  tok := sn_nueva_sesion('equipo', v, e.id, null, null, e.clave_temporal);
  return jsonb_build_object('ok', true, 'token', tok, 'tipo', 'equipo', 'equipo', sn_equipo_json(e.id),
                            'integrantes', sn_integrantes_json(e.id), 'cambiar_clave', e.clave_temporal);
end $$;

create or replace function public.sn_doc_recuperar(p_email text, p_respuesta text, p_nueva text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d record; k text; r text;
begin
  k := 'rec|' || lower(trim(coalesce(p_email,'')));
  if sn_bloqueado(k) then return jsonb_build_object('ok', false, 'error', 'bloqueado'); end if;
  if char_length(coalesce(p_nueva,'')) < 8 or char_length(p_nueva) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
  r := lower(regexp_replace(trim(coalesce(p_respuesta,'')), '\s+', ' ', 'g'));
  select * into d from sn_docentes where lower(email) = lower(trim(coalesce(p_email,''))) and activo and resp_hash <> '';
  if not found or d.resp_hash <> crypt(r, d.resp_hash) then
    perform sn_intento(k, false); perform pg_sleep(0.4);
    return jsonb_build_object('ok', false, 'error', 'datos');
  end if;
  perform sn_intento(k, true);
  update sn_docentes set clave_hash = crypt(p_nueva, gen_salt('bf')), clave_temporal = false where id = d.id;
  delete from sn_sesiones where docente_id = d.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sn_registrar_equipo(
  p_codigo text, p_nombre text, p_producto int, p_clave text, p_integrantes jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v uuid; ab boolean; nom text; eq uuid; a text; al text[] := '{}'; i int := 0; tok text;
begin
  v := sn_clase_por_codigo(p_codigo);
  if v is null then return jsonb_build_object('ok', false, 'error', 'codigo'); end if;
  select registro_abierto into ab from sn_clases where id = v;
  if not ab then return jsonb_build_object('ok', false, 'error', 'cerrado'); end if;
  nom := regexp_replace(trim(coalesce(p_nombre,'')), '\s+', ' ', 'g');
  if char_length(nom) < 3 or char_length(nom) > 40 then return jsonb_build_object('ok', false, 'error', 'nombre'); end if;
  if p_producto is null or p_producto not between 1 and 3 then return jsonb_build_object('ok', false, 'error', 'producto'); end if;
  if char_length(coalesce(p_clave,'')) < 4 or char_length(p_clave) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
  if jsonb_typeof(coalesce(p_integrantes,'null'::jsonb)) <> 'array' then return jsonb_build_object('ok', false, 'error', 'integrantes'); end if;
  for a in select jsonb_array_elements_text(p_integrantes) loop
    al := al || regexp_replace(trim(a), '\s+', ' ', 'g');
  end loop;
  if coalesce(array_length(al,1),0) < 1 or array_length(al,1) > 12 then return jsonb_build_object('ok', false, 'error', 'integrantes'); end if;
  foreach a in array al loop
    if char_length(a) < 2 or char_length(a) > 24 then return jsonb_build_object('ok', false, 'error', 'alias'); end if;
  end loop;
  if (select count(distinct lower(x)) from unnest(al) x) <> array_length(al,1) then
    return jsonb_build_object('ok', false, 'error', 'alias_repetido');
  end if;
  if (select count(*) from sn_equipos where clase_id = v) >= 30 then return jsonb_build_object('ok', false, 'error', 'limite'); end if;
  if exists (select 1 from sn_equipos where clase_id = v and lower(nombre) = lower(nom)) then
    return jsonb_build_object('ok', false, 'error', 'repetido');
  end if;
  insert into sn_equipos(clase_id, nombre, producto, clave_hash, clave_texto)
  values (v, nom, p_producto, crypt(p_clave, gen_salt('bf')), p_clave) returning id into eq;
  foreach a in array al loop insert into sn_integrantes(equipo_id, alias) values (eq, a); end loop;
  tok := sn_nueva_sesion('equipo', v, eq, null, null, false);
  return jsonb_build_object('ok', true, 'token', tok, 'tipo', 'equipo', 'equipo', sn_equipo_json(eq),
                            'integrantes', sn_integrantes_json(eq), 'cambiar_clave', false);
end $$;

create or replace function public.sn_cambiar_clave(p_token text, p_actual text, p_nueva text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; e record; d record;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is not null then
    if char_length(coalesce(p_nueva,'')) < 4 or char_length(p_nueva) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
    select * into e from sn_equipos where id = s.equipo_id;
    if e.clave_hash <> crypt(coalesce(p_actual,''), e.clave_hash) then return jsonb_build_object('ok', false, 'error', 'actual'); end if;
    if p_actual = p_nueva then return jsonb_build_object('ok', false, 'error', 'igual'); end if;
    update sn_equipos set clave_hash = crypt(p_nueva, gen_salt('bf')), clave_texto = p_nueva, clave_temporal = false where id = e.id;
    update sn_sesiones set tmp = false where token_hash = s.token_hash;
    return jsonb_build_object('ok', true, 'integrantes', sn_integrantes_json(e.id));
  end if;
  s := sn_ses(p_token, 'docente');
  if s.token_hash is not null then
    if char_length(coalesce(p_nueva,'')) < 8 or char_length(p_nueva) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
    select * into d from sn_docentes where id = s.docente_id;
    if d.clave_hash <> crypt(coalesce(p_actual,''), d.clave_hash) then return jsonb_build_object('ok', false, 'error', 'actual'); end if;
    if p_actual = p_nueva then return jsonb_build_object('ok', false, 'error', 'igual'); end if;
    update sn_docentes set clave_hash = crypt(p_nueva, gen_salt('bf')), clave_temporal = false where id = d.id;
    update sn_sesiones set tmp = false where token_hash = s.token_hash;
    return jsonb_build_object('ok', true);
  end if;
  return jsonb_build_object('ok', false, 'error', 'sesion');
end $$;

create or replace function public.sn_docente(p_token text, p_clase uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; v uuid; c record; o jsonb; si jsonb; n jsonb; eqs jsonb; cls jsonb;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre) order by creada desc), '[]'::jsonb) into cls from sn_clases;
  v := coalesce(p_clase, (select id from sn_clases where activa order by creada desc limit 1));
  select * into c from sn_clases where id = v;
  if not found then return jsonb_build_object('ok', true, 'clases', cls, 'clase', null); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'producto', e.producto, 'temporal', e.clave_temporal, 'clave', e.clave_texto,
           'integrantes', sn_integrantes_json(e.id)) order by e.creado), '[]'::jsonb) into eqs from sn_equipos e where e.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'inv', b.investigador, 'eq', e.nombre, 'prod', b.producto, 'pe', b.part_producto,
           'orden', b.orden, 'qd', b.q_d, 'gd', b.g_d, 'qr', b.q_r, 'gr', b.g_r, 'el', b.eleccion, 't', b.creada) order by b.id), '[]'::jsonb)
    into o from sn_obs b join sn_equipos e on e.id = b.equipo_id where b.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('inv', m.investigador, 'eq', e.nombre, 'prod', m.producto, 'datos', m.datos, 't', m.creada) order by m.id), '[]'::jsonb)
    into si from sn_sims m join sn_equipos e on e.id = m.equipo_id where m.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('inv', t.investigador, 'eq', e.nombre, 'nota', t.nota, 't', t.actualizada) order by t.investigador), '[]'::jsonb)
    into n from sn_notas t join sn_equipos e on e.id = t.equipo_id where t.clase_id = v;
  return jsonb_build_object('ok', true, 'clases', cls, 'clase', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'registro', c.registro_abierto),
                            'equipos', eqs, 'obs', o, 'sims', si, 'notas', n);
end $$;

create or replace function public.sn_docente_equipo(p_token text, p_accion text, p_equipo uuid, p_valor text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  if p_accion = 'reiniciar' then
    if char_length(coalesce(p_valor,'')) < 4 or char_length(p_valor) > 64 then return jsonb_build_object('ok', false, 'error', 'clave'); end if;
    update sn_equipos set clave_hash = crypt(p_valor, gen_salt('bf')), clave_texto = p_valor, clave_temporal = true where id = p_equipo;
    delete from sn_sesiones where equipo_id = p_equipo;
    delete from sn_intentos where clave = (select 'eq|' || clase_id::text || '|' || lower(nombre) from sn_equipos where id = p_equipo);
  elsif p_accion = 'borrar' then
    delete from sn_equipos where id = p_equipo;
  else
    return jsonb_build_object('ok', false, 'error', 'accion');
  end if;
  return jsonb_build_object('ok', true);
end $$;


-- Cuenta del docente: ver y cambiar la pregunta de seguridad
create or replace function public.sn_doc_cuenta_info(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; d record;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  select nombre, email, pregunta into d from sn_docentes where id = s.docente_id;
  return jsonb_build_object('ok', true, 'nombre', d.nombre, 'email', d.email, 'pregunta', d.pregunta);
end $$;

create or replace function public.sn_doc_cuenta(p_token text, p_clave text, p_pregunta text, p_respuesta text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; d record;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  select * into d from sn_docentes where id = s.docente_id;
  if d.clave_hash <> crypt(coalesce(p_clave,''), d.clave_hash) then perform pg_sleep(0.4); return jsonb_build_object('ok', false, 'error', 'actual'); end if;
  if char_length(trim(coalesce(p_pregunta,''))) < 8 or char_length(trim(coalesce(p_respuesta,''))) < 2 then
    return jsonb_build_object('ok', false, 'error', 'pregunta');
  end if;
  update sn_docentes set pregunta = trim(p_pregunta),
    resp_hash = crypt(lower(regexp_replace(trim(p_respuesta), '\s+', ' ', 'g')), gen_salt('bf')) where id = d.id;
  return jsonb_build_object('ok', true);
end $$;

-- Cambiar el código de clase
create or replace function public.sn_docente_codigo(p_token text, p_clase uuid, p_codigo text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  if char_length(trim(coalesce(p_codigo,''))) < 8 or char_length(p_codigo) > 64 then return jsonb_build_object('ok', false, 'error', 'codigo_corto'); end if;
  update sn_clases set cod_hash = crypt(upper(trim(p_codigo)), gen_salt('bf')) where id = p_clase;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.sn_doc_cuenta_info(text), public.sn_doc_cuenta(text,text,text,text), public.sn_docente_codigo(text,uuid,text) from public;
grant execute on function public.sn_doc_cuenta_info(text), public.sn_doc_cuenta(text,text,text,text), public.sn_docente_codigo(text,uuid,text) to anon, authenticated;


-- ---------- v4: el panel docente muestra el código de clase y la fecha de creación ----------
alter table public.sn_clases add column if not exists cod_texto text;

create or replace function public.sn_crear_clase(p_nombre text, p_codigo text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  if char_length(coalesce(p_codigo,'')) < 8 then raise exception 'El código debe tener al menos 8 caracteres'; end if;
  insert into sn_clases(nombre, cod_hash, cod_texto) values (p_nombre, crypt(upper(trim(p_codigo)), gen_salt('bf')), upper(trim(p_codigo))) returning id into v;
  return v;
end $$;

create or replace function public.sn_docente_codigo(p_token text, p_clase uuid, p_codigo text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  if char_length(trim(coalesce(p_codigo,''))) < 8 or char_length(p_codigo) > 64 then return jsonb_build_object('ok', false, 'error', 'codigo_corto'); end if;
  update sn_clases set cod_hash = crypt(upper(trim(p_codigo)), gen_salt('bf')), cod_texto = upper(trim(p_codigo)) where id = p_clase;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sn_docente(p_token text, p_clase uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; v uuid; c record; o jsonb; si jsonb; n jsonb; eqs jsonb; cls jsonb;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre) order by creada desc), '[]'::jsonb) into cls from sn_clases;
  v := coalesce(p_clase, (select id from sn_clases where activa order by creada desc limit 1));
  select * into c from sn_clases where id = v;
  if not found then return jsonb_build_object('ok', true, 'clases', cls, 'clase', null); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'nombre', e.nombre, 'producto', e.producto, 'temporal', e.clave_temporal, 'clave', e.clave_texto,
           'integrantes', sn_integrantes_json(e.id)) order by e.creado), '[]'::jsonb) into eqs from sn_equipos e where e.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'inv', b.investigador, 'eq', e.nombre, 'prod', b.producto, 'pe', b.part_producto,
           'orden', b.orden, 'qd', b.q_d, 'gd', b.g_d, 'qr', b.q_r, 'gr', b.g_r, 'el', b.eleccion, 't', b.creada) order by b.id), '[]'::jsonb)
    into o from sn_obs b join sn_equipos e on e.id = b.equipo_id where b.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('inv', m.investigador, 'eq', e.nombre, 'prod', m.producto, 'datos', m.datos, 't', m.creada) order by m.id), '[]'::jsonb)
    into si from sn_sims m join sn_equipos e on e.id = m.equipo_id where m.clase_id = v;
  select coalesce(jsonb_agg(jsonb_build_object('inv', t.investigador, 'eq', e.nombre, 'nota', t.nota, 't', t.actualizada) order by t.investigador), '[]'::jsonb)
    into n from sn_notas t join sn_equipos e on e.id = t.equipo_id where t.clase_id = v;
  return jsonb_build_object('ok', true, 'clases', cls, 'clase', jsonb_build_object('id', c.id, 'nombre', c.nombre, 'registro', c.registro_abierto, 'codigo', c.cod_texto, 'creada', c.creada),
                            'equipos', eqs, 'obs', o, 'sims', si, 'notas', n);
end $$;


-- ---------- v5: el docente ejecuta las rondas de simulación ----------
alter table public.sn_clases add column if not exists ronda int not null default 0;

create table if not exists public.sn_decisiones (
  clase_id      uuid not null references public.sn_clases(id) on delete cascade,
  equipo_id     uuid not null references public.sn_equipos(id) on delete cascade,
  integrante_id uuid not null references public.sn_integrantes(id) on delete cascade,
  investigador  text not null,
  ronda         int  not null,
  datos         jsonb not null,
  actualizada   timestamptz not null default now(),
  primary key (integrante_id, ronda)
);
alter table public.sn_decisiones enable row level security;
revoke all on public.sn_decisiones from anon, authenticated;

-- Estado de rondas para el estudiante: ronda ejecutada y sus decisiones
create or replace function public.sn_estado(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; r int; d jsonb;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  select ronda into r from sn_clases where id = s.clase_id;
  select coalesce(jsonb_agg(jsonb_build_object('ronda', x.ronda, 'datos', x.datos) order by x.ronda), '[]'::jsonb) into d
    from sn_decisiones x where x.integrante_id = s.integrante_id;
  return jsonb_build_object('ok', true, 'ronda', coalesce(r,0), 'decisiones', d);
end $$;

-- El estudiante guarda (o cambia) su decisión para la próxima ronda
create or replace function public.sn_guardar_decision(p_token text, p_datos jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; r int; alias text;
begin
  s := sn_ses(p_token, 'equipo');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp or s.integrante_id is null then return jsonb_build_object('ok', false, 'error', 'integrante'); end if;
  if p_datos is null or length(p_datos::text) > 2000 then return jsonb_build_object('ok', false, 'error', 'datos'); end if;
  select ronda into r from sn_clases where id = s.clase_id;
  select i.alias into alias from sn_integrantes i where i.id = s.integrante_id;
  insert into sn_decisiones(clase_id, equipo_id, integrante_id, investigador, ronda, datos)
  values (s.clase_id, s.equipo_id, s.integrante_id, alias, coalesce(r,0) + 1, p_datos)
  on conflict (integrante_id, ronda) do update set datos = excluded.datos, actualizada = now();
  return jsonb_build_object('ok', true, 'ronda', coalesce(r,0) + 1);
end $$;

-- El docente ejecuta la ronda (avanza el contador de la clase)
create or replace function public.sn_docente_ronda(p_token text, p_clase uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; r int;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  update sn_clases set ronda = ronda + 1 where id = p_clase returning ronda into r;
  return jsonb_build_object('ok', true, 'ronda', r);
end $$;

-- Panel: cuántas decisiones hay para la próxima ronda
create or replace function public.sn_docente_rondas(p_token text, p_clase uuid) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; r int; d jsonb;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  select ronda into r from sn_clases where id = p_clase;
  select coalesce(jsonb_agg(jsonb_build_object('inv', x.investigador, 'eq', e.nombre, 'ronda', x.ronda, 't', x.actualizada) order by e.nombre, x.investigador), '[]'::jsonb) into d
    from sn_decisiones x join sn_equipos e on e.id = x.equipo_id where x.clase_id = p_clase and x.ronda = coalesce(r,0) + 1;
  return jsonb_build_object('ok', true, 'ronda', coalesce(r,0), 'pendientes', d);
end $$;

revoke all on function public.sn_estado(text), public.sn_guardar_decision(text,jsonb), public.sn_docente_ronda(text,uuid), public.sn_docente_rondas(text,uuid) from public;
grant execute on function public.sn_estado(text), public.sn_guardar_decision(text,jsonb), public.sn_docente_ronda(text,uuid), public.sn_docente_rondas(text,uuid) to anon, authenticated;


-- ---------- v7: el docente crea, archiva y elimina simulaciones (clases) ----------
create or replace function public.sn_docente_clases(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare s sn_sesiones; d jsonb;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'nombre', c.nombre, 'codigo', c.cod_texto, 'creada', c.creada,
           'activa', c.activa, 'registro', c.registro_abierto, 'ronda', c.ronda,
           'equipos', (select count(*) from sn_equipos e where e.clase_id = c.id)) order by c.creada desc), '[]'::jsonb)
    into d from sn_clases c;
  return jsonb_build_object('ok', true, 'clases', d);
end $$;

create or replace function public.sn_docente_crear_clase(p_token text, p_nombre text, p_codigo text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones; v uuid; c text := upper(trim(coalesce(p_codigo,''))); n text := trim(coalesce(p_nombre,''));
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  if char_length(n) < 3 or char_length(n) > 80 then return jsonb_build_object('ok', false, 'error', 'nombre_clase'); end if;
  if char_length(c) < 8 or char_length(c) > 64 then return jsonb_build_object('ok', false, 'error', 'codigo_corto'); end if;
  if exists (select 1 from sn_clases where cod_hash = crypt(c, cod_hash)) then return jsonb_build_object('ok', false, 'error', 'codigo_usado'); end if;
  insert into sn_clases(nombre, cod_hash, cod_texto) values (n, crypt(c, gen_salt('bf')), c) returning id into v;
  return jsonb_build_object('ok', true, 'id', v);
end $$;

create or replace function public.sn_docente_clase_estado(p_token text, p_clase uuid, p_activa boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  update sn_clases set activa = coalesce(p_activa, activa) where id = p_clase;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sn_docente_borrar_clase(p_token text, p_clase uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sn_sesiones;
begin
  s := sn_ses(p_token, 'docente');
  if s.token_hash is null then return jsonb_build_object('ok', false, 'error', 'sesion'); end if;
  if s.tmp then return jsonb_build_object('ok', false, 'error', 'tmp'); end if;
  delete from sn_sesiones where clase_id = p_clase and rol = 'equipo';
  delete from sn_clases where id = p_clase;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.sn_docente_clases(text), public.sn_docente_crear_clase(text,text,text), public.sn_docente_clase_estado(text,uuid,boolean), public.sn_docente_borrar_clase(text,uuid) from public;
grant execute on function public.sn_docente_clases(text), public.sn_docente_crear_clase(text,text,text), public.sn_docente_clase_estado(text,uuid,boolean), public.sn_docente_borrar_clase(text,uuid) to anon, authenticated;


-- ---------- Preparar el curso (edita los valores y ejecuta estas dos líneas) ----------
-- 1) La clase: el código que darás a los estudiantes (mín. 8 caracteres)
-- select public.sn_crear_clase('UAB Mercadeo Estratégico 2026', 'CODIGO-DE-CLASE');
-- 2) Tu usuario de docente (contraseña temporal: la cambiarás al primer ingreso)
-- select public.sn_crear_docente('Jhonny Atila', 'tu-correo@ejemplo.com', 'CLAVE-TEMPORAL-8+', 'Pregunta secreta que solo tú sepas', 'respuesta');
