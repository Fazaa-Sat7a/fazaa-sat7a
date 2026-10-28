-- Fazaa Admin 0.1.0. Requires commercial migrations 07-10; additive, existing clients unchanged.
begin;
create table if not exists public.fazaa_admin_members(
 user_id uuid primary key references auth.users(id), role text not null check(role in ('admin','operations','accountant','disabled')), updated_at timestamptz not null default now());
create table if not exists public.fazaa_admin_audit(
 id bigint generated always as identity primary key, actor uuid, actor_role text, action text not null, entity text not null,
 before_value jsonb, after_value jsonb, created_at timestamptz not null default now());
alter table public.fazaa_admin_members enable row level security;
alter table public.fazaa_admin_audit enable row level security;
revoke all on public.fazaa_admin_members,public.fazaa_admin_audit from public,anon,authenticated;
create or replace function public.fazaa_admin_role() returns text language sql stable security definer set search_path='' as $$
 select case when coalesce(public.is_admin(),false) then 'admin' else coalesce((select role from public.fazaa_admin_members where user_id=auth.uid()),'none') end
$$;
create or replace function public.fazaa_admin_require(p_area text) returns void language plpgsql stable security definer set search_path='' as $$
declare r text:=public.fazaa_admin_role();begin
 if auth.uid() is null or not coalesce((r='admin' or (r='operations' and p_area in ('home','operations','ratings')) or (r='accountant' and p_area in ('home','finance'))),false) then raise exception 'ADMIN_PERMISSION_REQUIRED';end if;
end $$;
create or replace function public.fazaa_admin_audit_change() returns trigger language plpgsql security definer set search_path='' as $$
declare b jsonb; a jsonb;r text:=public.fazaa_admin_role();begin
 if r not in ('admin','operations','accountant') then return null;end if;
 if TG_OP<>'INSERT' then b:=to_jsonb(old);end if;
 if TG_OP<>'DELETE' then a:=to_jsonb(new);end if;
 -- Avoid tracking GPS heartbeats; audit administrative profile/availability changes only.
 if TG_TABLE_NAME='drivers' then b:=b-'lat'-'lng'-'location_updated_at';a:=a-'lat'-'lng'-'location_updated_at';end if;
 if b is not distinct from a then return null;end if;
 insert into public.fazaa_admin_audit(actor,actor_role,action,entity,before_value,after_value) values(auth.uid(),r,TG_OP,TG_TABLE_NAME,b,a);
 return null;
end $$;
do $$ declare t text;begin
 foreach t in array array['drivers','fazaa_fare_settings','fazaa_truck_classes','fazaa_fare_zones','fazaa_tariffs','fazaa_driver_fleet','fazaa_driver_ledger','fazaa_admin_members'] loop
 execute format('drop trigger if exists fazaa_admin_audit on public.%I',t);
 execute format('create trigger fazaa_admin_audit after insert or update or delete on public.%I for each row execute function public.fazaa_admin_audit_change()',t);
 end loop;
end $$;
create or replace function public.admin_app_home() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text;begin
 perform public.fazaa_admin_require('home');r:=public.fazaa_admin_role();
 return jsonb_build_object('role',r,'user_id',auth.uid(),'time',now(),
 'waiting',case when r<>'accountant' then (select count(*) from public.requests where status='new' and created_at>now()-interval '15 minutes') else 0 end,
 'active',case when r<>'accountant' then (select count(*) from public.requests where status in ('accepted','arrived','in_progress')) else 0 end,
 'available',case when r<>'accountant' then (select count(*) from public.drivers where status='active' and is_available and location_updated_at>now()-interval '5 minutes') else 0 end,
 'stale',case when r<>'accountant' then (select count(*) from public.drivers where status='active' and is_available and (location_updated_at is null or location_updated_at<=now()-interval '5 minutes')) else 0 end,
 'overdue',case when r<>'accountant' then (select count(*) from public.requests where status='new' and created_at between now()-interval '15 minutes' and now()-interval '5 minutes') else 0 end);
end $$;
create or replace function public.admin_app_requests(p_query text default '',p_status text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.fazaa_admin_require('operations');
 return coalesce((select jsonb_agg(x.data) from (select to_jsonb(r)||jsonb_build_object('driver_name',d.name,'driver_phone',d.phone) data from public.requests r left join public.drivers d on d.id=r.driver_id
 where (p_status='' or r.status=p_status) and (p_query='' or r.short_code ilike '%'||left(p_query,100)||'%' or r.customer_phone ilike '%'||left(p_query,100)||'%' or r.id::text=trim(p_query))
 order by r.created_at desc,r.id desc limit 31 offset greatest(0,p_offset)) x),'[]'::jsonb);
end $$;
create or replace function public.admin_app_drivers(p_query text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.fazaa_admin_require('operations');
 return coalesce((select jsonb_agg(x.data) from (select to_jsonb(d) data from public.drivers d where p_query='' or d.name ilike '%'||left(p_query,100)||'%' or d.phone ilike '%'||left(p_query,100)||'%' or d.plate ilike '%'||left(p_query,100)||'%'
 order by d.created_at desc,d.id limit 31 offset greatest(0,p_offset))x),'[]'::jsonb);
end $$;
create or replace function public.admin_app_ratings(p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform public.fazaa_admin_require('ratings');return coalesce((select jsonb_agg(x.data) from (select to_jsonb(r)||jsonb_build_object('driver_name',d.name) data from public.ratings r join public.drivers d on d.id=r.driver_id order by r.created_at desc,r.id limit 31 offset greatest(0,p_offset))x),'[]'::jsonb);end $$;
create or replace function public.admin_app_audit(p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform public.fazaa_admin_require('admin');return coalesce((select jsonb_agg(to_jsonb(x)) from (select a.*,u.email actor_email from public.fazaa_admin_audit a left join auth.users u on u.id=a.actor order by a.id desc limit 31 offset greatest(0,p_offset))x),'[]'::jsonb);end $$;
create or replace function public.admin_app_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform public.fazaa_admin_require('admin');return coalesce((select jsonb_agg(jsonb_build_object('user_id',m.user_id,'role',m.role,'email',u.email)) from public.fazaa_admin_members m join auth.users u on u.id=m.user_id),'[]'::jsonb);end $$;
create or replace function public.admin_app_member(p_email text,p_role text) returns void language plpgsql security definer set search_path='' as $$
declare target uuid;begin
 perform public.fazaa_admin_require('admin');
 if p_role not in ('admin','operations','accountant','disabled') then raise exception 'INVALID_ROLE';end if;
 select id into target from auth.users where lower(email)=lower(trim(p_email)) and email_confirmed_at is not null;
 if not found then raise exception 'CONFIRMED_ACCOUNT_REQUIRED';end if;
 if target=auth.uid() or exists(select 1 from public.admins where id=target) then raise exception 'CORE_ADMIN_PROTECTED';end if;
 insert into public.fazaa_admin_members(user_id,role) values(target,p_role) on conflict(user_id) do update set role=excluded.role,updated_at=now();
end $$;
create or replace function public.admin_app_driver(p_id uuid,p_action text,p_values jsonb default '{}') returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.fazaa_admin_require('operations');
 if p_action='save' then
  if p_id is null then select id into p_id from auth.users where lower(email)=lower(trim(p_values->>'email')) and email_confirmed_at is not null;if not found then raise exception 'CONFIRMED_ACCOUNT_REQUIRED';end if;end if;
  if length(trim(p_values->>'name')) not between 1 and 100 or coalesce(trim(p_values->>'name'),'')='' or coalesce(p_values->>'phone','') !~ '^\+?[0-9]{7,15}$' or coalesce(trim(p_values->>'plate'),'')='' then raise exception 'INVALID_DRIVER_DETAILS';end if;
  if not exists(select 1 from auth.users where id=p_id) then raise exception 'ACCOUNT_REQUIRED';end if;
  insert into public.drivers(id,name,phone,plate,truck_type,area,status,is_available) values(p_id,trim(p_values->>'name'),p_values->>'phone',p_values->>'plate',coalesce(p_values->>'truck_type','standard'),p_values->>'area','active',false)
  on conflict(id) do update set name=excluded.name,phone=excluded.phone,plate=excluded.plate,truck_type=excluded.truck_type,area=excluded.area;
 elsif p_action in ('suspend','activate','stop') then
  perform 1 from public.drivers where id=p_id for update;
  if not found then raise exception 'DRIVER_NOT_FOUND';end if;
  if p_action='suspend' and exists(select 1 from public.requests where driver_id=p_id and status in ('accepted','arrived','in_progress')) then raise exception 'ACTIVE_TRIP_EXISTS';end if;
  update public.drivers set is_available=false,status=case when p_action='suspend' then 'suspended' when p_action='activate' then 'active' else status end where id=p_id;
 else raise exception 'INVALID_ACTION';end if;
end $$;
create or replace function public.admin_app_commercial()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform public.fazaa_admin_require('home');
 return jsonb_build_object('settings',case when public.fazaa_admin_role()='operations' then '{}'::jsonb else (select to_jsonb(s) from public.fazaa_fare_settings s where id) end,
 'classes',coalesce((select jsonb_agg(to_jsonb(c) order by name) from public.fazaa_truck_classes c),'[]'::jsonb),
 
 'zones',coalesce((select jsonb_agg(to_jsonb(z)) from public.fazaa_fare_zones z),'[]'::jsonb),
 'tariffs',case when public.fazaa_admin_role()='operations' then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(t)) from public.fazaa_tariffs t),'[]'::jsonb) end,
 'fleet',coalesce((select jsonb_agg((case when public.fazaa_admin_role()='operations' then to_jsonb(f)-'credit_limit' else to_jsonb(f) end)||jsonb_build_object('name',d.name,'balance',case when public.fazaa_admin_role()='operations' then null else public.fazaa_driver_balance(d.id) end)) from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id),'[]'::jsonb),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'plate',plate)) from public.drivers),'[]'::jsonb),
 'regions',(select jsonb_agg(jsonb_build_object('code',code,'name',name)) from public.customer_regions),
 'ledger',case when public.fazaa_admin_role()='operations' then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(x)) from (select l.*,d.name from public.fazaa_driver_ledger l join public.drivers d on d.id=l.driver_id order by l.created_at desc limit 100)x),'[]'::jsonb) end);
end $$;
create or replace function public.admin_app_save_commercial(p_kind text,p_values jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare ident uuid; setting public.fazaa_fare_settings%rowtype; field text; value text;
begin
 perform public.fazaa_admin_require(case when p_kind in ('fleet','class','zone') then 'operations' when p_kind in ('settings','tariff') then 'finance' else 'admin' end);
 select * into setting from public.fazaa_fare_settings where id for update;
 if p_kind='fleet' and public.fazaa_admin_role()='operations' then p_values:=p_values||jsonb_build_object('credit_limit',(select credit_limit from public.fazaa_driver_fleet where driver_id=(p_values->>'driver_id')::uuid));end if;
 foreach field in array array['commission_pct','credit_limit','length_m','width_m','capacity_kg','height_m','weight_kg','south','west','north','east','start_fee','per_km','per_minute','loading_fee','unloading_fee','minimum_fare','rounding_unit'] loop
  value:=p_values->>field;
  if nullif(value,'') is not null and (value::numeric::text in ('NaN','Infinity','-Infinity') or abs(value::numeric)>99999999999) then raise exception 'INVALID_NUMBER'; end if;
 end loop;
 if p_kind='settings' then
  if coalesce((p_values->>'commission_pct')::numeric,0)>0 and nullif(p_values->>'credit_limit','') is null then raise exception 'CREDIT_LIMIT_REQUIRED'; end if;
  if p_values->>'commission_pct' is null then raise exception 'COMMISSION_REQUIRED'; end if;
  if p_values->>'currency_label' is null or length(p_values->>'currency_label') not between 1 and 30 then raise exception 'INVALID_CURRENCY'; end if;
  -- A currency unit is a financial identity, not a cosmetic label once priced trips exist.
  if p_values->>'currency_label'<>setting.currency_label and exists(select 1 from public.requests where fare_quote_id is not null) then raise exception 'CURRENCY_LOCKED'; end if;
  if (p_values->>'enabled')::boolean and not exists(select 1 from public.fazaa_tariffs t join public.fazaa_fare_zones z on z.region_code=t.region_code and z.enabled join public.fazaa_truck_classes c on c.id=t.truck_class_id and c.enabled where t.enabled) then raise exception 'CONFIGURATION_INCOMPLETE'; end if;
  if (p_values->>'enabled')::boolean and (not exists(select 1 from public.fazaa_driver_fleet where cardinality(approved_categories)>0) or not exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id where d.status='active')) then raise exception 'CONFIGURATION_INCOMPLETE'; end if;
  update public.fazaa_fare_settings set enabled=(p_values->>'enabled')::boolean,commission_pct=(p_values->>'commission_pct')::numeric,currency_label=p_values->>'currency_label',credit_limit=nullif(p_values->>'credit_limit','')::numeric,settlement_days=(p_values->>'settlement_days')::integer where id;
 elsif p_kind='class' then
  if nullif(p_values->>'height_m','')::numeric<=0 then raise exception 'INVALID_NUMBER';end if;
  ident:=coalesce(nullif(p_values->>'id','')::uuid,gen_random_uuid());
  insert into public.fazaa_truck_classes(id,name,enclosed,length_m,width_m,capacity_kg,height_m,enabled,priority) values(ident,p_values->>'name',(p_values->>'enclosed')::boolean,nullif(p_values->>'length_m','')::numeric,nullif(p_values->>'width_m','')::numeric,nullif(p_values->>'capacity_kg','')::numeric,nullif(p_values->>'height_m','')::numeric,(p_values->>'enabled')::boolean,coalesce((p_values->>'priority')::integer,100))
  on conflict(id) do update set name=excluded.name,enclosed=excluded.enclosed,length_m=excluded.length_m,width_m=excluded.width_m,capacity_kg=excluded.capacity_kg,height_m=excluded.height_m,enabled=excluded.enabled,priority=excluded.priority;
 elsif p_kind='vehicle' then
  ident:=coalesce(nullif(p_values->>'id','')::uuid,gen_random_uuid());
  insert into public.fazaa_vehicle_models(id,make,model,car_type,length_m,width_m,height_m,weight_kg,year_from,year_to,enabled) values(ident,p_values->>'make',p_values->>'model',p_values->>'car_type',(p_values->>'length_m')::numeric,(p_values->>'width_m')::numeric,(p_values->>'height_m')::numeric,(p_values->>'weight_kg')::numeric,(p_values->>'year_from')::integer,(p_values->>'year_to')::integer,(p_values->>'enabled')::boolean)
  on conflict(id) do update set make=excluded.make,model=excluded.model,car_type=excluded.car_type,length_m=excluded.length_m,width_m=excluded.width_m,height_m=excluded.height_m,weight_kg=excluded.weight_kg,year_from=excluded.year_from,year_to=excluded.year_to,enabled=excluded.enabled;
 elsif p_kind='zone' then
  insert into public.fazaa_fare_zones(region_code,south,west,north,east,enabled) values(p_values->>'region_code',(p_values->>'south')::numeric,(p_values->>'west')::numeric,(p_values->>'north')::numeric,(p_values->>'east')::numeric,(p_values->>'enabled')::boolean)
  on conflict(region_code) do update set south=excluded.south,west=excluded.west,north=excluded.north,east=excluded.east,enabled=excluded.enabled;
 elsif p_kind='tariff' then
  insert into public.fazaa_tariffs(region_code,truck_class_id,start_fee,per_km,per_minute,loading_fee,unloading_fee,minimum_fare,rounding_unit,enabled) values(p_values->>'region_code',(p_values->>'truck_class_id')::uuid,(p_values->>'start_fee')::numeric,(p_values->>'per_km')::numeric,(p_values->>'per_minute')::numeric,(p_values->>'loading_fee')::numeric,(p_values->>'unloading_fee')::numeric,(p_values->>'minimum_fare')::numeric,(p_values->>'rounding_unit')::numeric,(p_values->>'enabled')::boolean)
  on conflict(region_code,truck_class_id) do update set start_fee=excluded.start_fee,per_km=excluded.per_km,per_minute=excluded.per_minute,loading_fee=excluded.loading_fee,unloading_fee=excluded.unloading_fee,minimum_fare=excluded.minimum_fare,rounding_unit=excluded.rounding_unit,enabled=excluded.enabled;
 elsif p_kind='fleet' then
  if p_values ? 'approved_categories' then
   if jsonb_typeof(p_values->'approved_categories') is distinct from 'array' then raise exception 'INVALID_CATEGORIES';end if;
   if exists(select 1 from jsonb_array_elements_text(p_values->'approved_categories') x(value) where not exists(select 1 from public.fazaa_vehicle_categories where code=x.value)) then raise exception 'INVALID_CATEGORIES';end if;
  end if;
  insert into public.fazaa_driver_fleet(driver_id,truck_class_id,region_code,credit_limit) values((p_values->>'driver_id')::uuid,(p_values->>'truck_class_id')::uuid,p_values->>'region_code',nullif(p_values->>'credit_limit','')::numeric)
  on conflict(driver_id) do update set truck_class_id=excluded.truck_class_id,region_code=excluded.region_code,credit_limit=excluded.credit_limit;
  if p_values ? 'approved_categories' then
   update public.fazaa_driver_fleet set approved_categories=array(select distinct jsonb_array_elements_text(p_values->'approved_categories')) where driver_id=(p_values->>'driver_id')::uuid;
  end if;
 else raise exception 'INVALID_KIND'; end if;
 update public.fazaa_fare_settings set revision=revision+1 where id;
end $$;
create or replace function public.admin_app_settlement(p_driver uuid,p_amount numeric,p_reference text,p_note text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; existing public.fazaa_driver_ledger%rowtype;
begin
 perform public.fazaa_admin_require('finance');
 if p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or round(p_amount,2)<>p_amount or length(trim(p_reference)) not between 3 and 100 then raise exception 'INVALID_SETTLEMENT'; end if;
 perform pg_advisory_xact_lock(hashtextextended('fare-driver:'||p_driver::text,0));
 select * into existing from public.fazaa_driver_ledger where reference=trim(p_reference) and kind='settlement';
 if found then
  if existing.driver_id<>p_driver or existing.amount<>-p_amount then raise exception 'REFERENCE_ALREADY_USED'; end if;
  return existing.id;
 end if;
 insert into public.fazaa_driver_ledger(driver_id,kind,amount,note,reference,created_by) values(p_driver,'settlement',-p_amount,left(p_note,300),trim(p_reference),auth.uid()) returning id into result;
 return result;
end $$;
do $$ declare f record;begin
 for f in select oid::regprocedure signature,proname from pg_proc where pronamespace='public'::regnamespace and (proname like 'admin_app_%' or proname in ('fazaa_admin_role','fazaa_admin_require','fazaa_admin_audit_change')) loop
 execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 if f.proname like 'admin_app_%' then execute format('grant execute on function %s to authenticated',f.signature);end if;
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
