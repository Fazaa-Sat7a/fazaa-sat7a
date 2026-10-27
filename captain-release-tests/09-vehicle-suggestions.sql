begin;

create table if not exists public.fazaa_vehicle_suggestions(
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id),
 make text not null check(length(make) between 1 and 80),
 model text not null check(length(model) between 1 and 80),
 model_year integer check(model_year between 1900 and 2200),
 status text not null default 'pending' check(status in ('pending','reviewed','rejected')),
 created_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid references auth.users(id)
);
create index if not exists fazaa_suggestion_customer_date on public.fazaa_vehicle_suggestions(customer_id,created_at);
create unique index if not exists fazaa_suggestion_pending_unique on public.fazaa_vehicle_suggestions(customer_id,lower(make),lower(model),coalesce(model_year,0)) where status='pending';
alter table public.fazaa_vehicle_suggestions enable row level security;
revoke all on public.fazaa_vehicle_suggestions from public,anon,authenticated;

create table if not exists public.fazaa_vehicle_model_sources(
 vehicle_id uuid primary key references public.fazaa_vehicle_models(id) on delete cascade,
 source text not null check(length(source) between 1 and 1000),
 checked_by uuid not null references auth.users(id),checked_at timestamptz not null default now()
);
alter table public.fazaa_vehicle_model_sources enable row level security;
revoke all on public.fazaa_vehicle_model_sources from public,anon,authenticated;

create or replace function public.submit_fazaa_vehicle_suggestion(p_make text,p_model text,p_year integer default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare ident uuid; clean_make text:=btrim(p_make);clean_model text:=btrim(p_model);
begin
 if not exists(select 1 from auth.users where id=auth.uid() and email is not null and email_confirmed_at is not null) then raise exception 'SIGN_IN_REQUIRED';end if;
 if clean_make is null or clean_model is null or length(clean_make) not between 1 and 80 or length(clean_model) not between 1 and 80 or (p_year is not null and (p_year<1900 or p_year>extract(year from now())::integer+2)) then raise exception 'INVALID_VEHICLE';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fazaa-suggestion:'||auth.uid()::text,0));
 select id into ident from public.fazaa_vehicle_suggestions where customer_id=auth.uid() and lower(make)=lower(clean_make) and lower(model)=lower(clean_model) and model_year is not distinct from p_year and status='pending';
 if ident is not null then return ident;end if;
 if (select count(*) from public.fazaa_vehicle_suggestions where customer_id=auth.uid() and created_at>now()-interval '24 hours')>=10 then raise exception 'SUGGESTION_RATE_LIMIT';end if;
 insert into public.fazaa_vehicle_suggestions(customer_id,make,model,model_year) values(auth.uid(),clean_make,clean_model,p_year) returning id into ident;
 return ident;
end $$;

create or replace function public.admin_get_fazaa_vehicle_suggestions()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from(select s.id,s.make,s.model,s.model_year,s.status,s.created_at,u.email from public.fazaa_vehicle_suggestions s join auth.users u on u.id=s.customer_id order by s.created_at desc limit 300)x),'[]'::jsonb);
end $$;

create or replace function public.admin_review_fazaa_vehicle_suggestion(p_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if p_status not in ('reviewed','rejected') or p_status is null then raise exception 'INVALID_STATUS';end if;
 update public.fazaa_vehicle_suggestions set status=p_status,reviewed_at=now(),reviewed_by=auth.uid() where id=p_id and status='pending';
end $$;

create or replace function public.admin_import_fazaa_vehicle_models(p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare item jsonb;ident uuid;field text;counted integer:=0;source_text text;
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'INVALID_IMPORT';end if;
 if jsonb_array_length(p_rows) not between 1 and 500 or octet_length(p_rows::text)>2000000 then raise exception 'INVALID_IMPORT';end if;
 perform 1 from public.fazaa_fare_settings where id for update;
 for item in select value from jsonb_array_elements(p_rows) loop
  if jsonb_typeof(item) is distinct from 'object' then raise exception 'INVALID_IMPORT_ROW';end if;
  foreach field in array array['make','model','source'] loop
   if jsonb_typeof(item->field) is distinct from 'string' or nullif(btrim(item->>field),'') is null then raise exception 'INVALID_IMPORT_ROW';end if;
  end loop;
  if length(item->>'make')>80 or length(item->>'model')>80 or length(item->>'source')>1000 or item->>'car_type' not in ('small','suv','truck') or item->>'car_type' is null then raise exception 'INVALID_IMPORT_ROW';end if;
  foreach field in array array['length_m','width_m','height_m','weight_kg','year_from','year_to'] loop
   if jsonb_typeof(item->field) is distinct from 'number' then raise exception 'INVALID_IMPORT_ROW';end if;
  end loop;
  if (item->>'length_m')::numeric<=0 or (item->>'width_m')::numeric<=0 or (item->>'height_m')::numeric<=0 or (item->>'weight_kg')::numeric<=0 or (item->>'year_from')::numeric<>trunc((item->>'year_from')::numeric) or (item->>'year_to')::numeric<>trunc((item->>'year_to')::numeric) or (item->>'year_from')::integer<1900 or (item->>'year_to')::integer>2200 or (item->>'year_from')::integer>(item->>'year_to')::integer then raise exception 'INVALID_IMPORT_ROW';end if;
  if item ? 'enabled' and jsonb_typeof(item->'enabled') is distinct from 'boolean' then raise exception 'INVALID_IMPORT_ROW';end if;
  item:=item||jsonb_build_object('enabled',coalesce((item->>'enabled')::boolean,false),'make',btrim(item->>'make'),'model',btrim(item->>'model'));
  select id into ident from public.fazaa_vehicle_models where lower(make)=lower(item->>'make') and lower(model)=lower(item->>'model') and year_from=(item->>'year_from')::integer and year_to=(item->>'year_to')::integer order by id limit 1;
  ident:=coalesce(ident,gen_random_uuid());source_text:=btrim(item->>'source');
  perform public.admin_save_fazaa_commercial('vehicle',item||jsonb_build_object('id',ident));
  insert into public.fazaa_vehicle_model_sources(vehicle_id,source,checked_by) values(ident,source_text,auth.uid()) on conflict(vehicle_id) do update set source=excluded.source,checked_by=excluded.checked_by,checked_at=now();
  counted:=counted+1;
 end loop;
 return counted;
end $$;

revoke all on function public.submit_fazaa_vehicle_suggestion(text,text,integer),public.admin_get_fazaa_vehicle_suggestions(),public.admin_review_fazaa_vehicle_suggestion(uuid,text),public.admin_import_fazaa_vehicle_models(jsonb) from public,anon,authenticated;
grant execute on function public.submit_fazaa_vehicle_suggestion(text,text,integer),public.admin_get_fazaa_vehicle_suggestions(),public.admin_review_fazaa_vehicle_suggestion(uuid,text),public.admin_import_fazaa_vehicle_models(jsonb) to authenticated;
commit;
