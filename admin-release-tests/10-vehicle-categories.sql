-- Fazaa customer 0.5.0. Apply AFTER 07,08,09. No automatic fleet approvals or pricing activation.
begin;
create table if not exists public.fazaa_vehicle_categories(code text primary key,label text not null,car_type text not null check(car_type in ('small','suv','truck')),sort_order integer not null);
insert into public.fazaa_vehicle_categories values
 ('passenger','سيارة ركوب','small',1),('crossover','كروس أوفر / SUV متوسطة','suv',2),('suv_large','SUV كبيرة','suv',3),('low_clearance','سيارة رياضية أو منخفضة','small',4),('pickup','بيك أب','truck',5),('van','فان / ميني فان','truck',6)
on conflict(code) do update set label=excluded.label,car_type=excluded.car_type,sort_order=excluded.sort_order;
alter table public.fazaa_vehicle_categories enable row level security;
revoke all on public.fazaa_vehicle_categories from public,anon,authenticated;
alter table public.fazaa_driver_fleet add column if not exists approved_categories text[] not null default '{}';
alter table public.fazaa_truck_classes add column if not exists priority integer not null default 100 check(priority between 1 and 10000);
alter table public.fazaa_truck_classes alter column length_m drop not null,alter column width_m drop not null,alter column capacity_kg drop not null;
-- Remove only the old requirement that enclosed trucks MUST have a height entered.
do $$ declare c record;begin
 for c in select conname from pg_constraint where conrelid='public.fazaa_truck_classes'::regclass and contype='c' and pg_get_constraintdef(oid) like '%enclosed%' and pg_get_constraintdef(oid) like '%height_m%' loop
 execute format('alter table public.fazaa_truck_classes drop constraint %I',c.conname);end loop;
end $$;
alter table public.fazaa_fare_quotes alter column vehicle_id drop not null;
alter table public.requests add column if not exists vehicle_category text references public.fazaa_vehicle_categories(code);
alter table public.requests add column if not exists vehicle_description text;
alter table public.requests add column if not exists requested_enclosed boolean;
create or replace function public.get_fazaa_category_catalog()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('categories',(select jsonb_agg(to_jsonb(c) order by sort_order) from public.fazaa_vehicle_categories c),
 'matches',coalesce((select jsonb_agg(jsonb_build_object('category_code',v.code,'region_code',p.region_code,'enclosed',c.enclosed,'truck_name',c.name) order by c.priority,c.id)
 from public.fazaa_vehicle_categories v cross join public.fazaa_truck_classes c join public.fazaa_tariffs p on p.truck_class_id=c.id and p.enabled
 where c.enabled and exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id where f.truck_class_id=c.id and f.region_code=p.region_code and d.status='active' and v.code=any(f.approved_categories))),'[]'::jsonb));
$$;
revoke all on function public.get_fazaa_category_catalog() from public,anon;
grant execute on function public.get_fazaa_category_catalog() to authenticated;
create or replace function public.prepare_fazaa_quote(p_input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.fazaa_fare_settings%rowtype; v public.fazaa_vehicle_models%rowtype;
 t public.fazaa_truck_classes%rowtype; price public.fazaa_tariffs%rowtype; r public.requests%rowtype;
 zone public.fazaa_fare_zones%rowtype; pickup jsonb; stops jsonb; points jsonb; item jsonb;
 terms jsonb; chosen uuid; region text; yr integer; parent uuid; version integer:=0; ticket uuid;
 requested_enclosed boolean; current_stops jsonb; category public.fazaa_vehicle_categories%rowtype; description text;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended('fare-quote:'||auth.uid()::text,0));
 select * into s from public.fazaa_fare_settings where id for share;
 if not (s.enabled or public.fazaa_is_trial_customer()) then raise exception 'PRICING_NOT_READY'; end if;
 if (select count(*) from public.fazaa_fare_quotes where customer_id=auth.uid() and created_at>now()-interval '15 minutes')>=15 then raise exception 'QUOTE_RATE_LIMIT'; end if;
 if jsonb_typeof(p_input)<>'object' then raise exception 'INVALID_INPUT'; end if;
 parent:=nullif(p_input->>'request_id','')::uuid;
 if parent is not null then
  select * into r from public.requests where id=parent;
  if not found or not public.customer_can_access(parent) or r.fare_quote_id is null or r.status not in ('accepted','arrived','in_progress') then raise exception 'CHANGE_NOT_ALLOWED'; end if;
  version:=r.fare_revision; region:=r.region_code; chosen:=r.fare_truck_class; terms:=r.fare_terms;
  pickup:=r.fare_stops->(jsonb_array_length(r.fare_stops)-1); current_stops:=r.fare_stops;
  select * into v from public.fazaa_vehicle_models where id=r.fare_vehicle_id;
  yr:=r.fare_vehicle_year;
 else
  region:=p_input->>'region_code'; pickup:=p_input->'pickup';
  requested_enclosed:=coalesce((p_input->>'enclosed')::boolean,false); yr:=nullif(p_input->>'vehicle_year','')::integer;
  if p_input ? 'category_code' then
   select * into category from public.fazaa_vehicle_categories where code=p_input->>'category_code';
   if not found then raise exception 'VEHICLE_NOT_APPROVED';end if;
   description:=btrim(p_input->>'vehicle_name');
   if description is null or length(description) not between 2 and 100 then raise exception 'INVALID_DETAILS';end if;
   if (requested_enclosed and yr is null) or (yr is not null and yr not between 1900 and extract(year from now())::integer+1) then raise exception 'VEHICLE_YEAR_REQUIRED';end if;
  else
   -- Keep old model-based clients and existing quoted trips compatible during deployment.
   select * into v from public.fazaa_vehicle_models where id=(p_input->>'vehicle_id')::uuid and enabled;
   if not found then raise exception 'VEHICLE_NOT_APPROVED';end if;
   if (requested_enclosed and yr is null) or (yr is not null and yr not between v.year_from and v.year_to) then raise exception 'VEHICLE_YEAR_REQUIRED';end if;
  end if;
  select * into zone from public.fazaa_fare_zones where region_code=region and enabled;
  if not found or not public.fazaa_point_ok(pickup) then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  if (pickup->>'lat')::numeric not between zone.south and zone.north or (pickup->>'lng')::numeric not between zone.west and zone.east then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  if not exists(select 1 from public.customer_service_coverage c join public.customer_regions cr on cr.code=c.region_code where c.region_code=region and c.service_code='tow' and c.enabled and cr.enabled) then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  select c.* into t from public.fazaa_truck_classes c join public.fazaa_tariffs p on p.truck_class_id=c.id and p.region_code=region and p.enabled
   where c.enabled and c.enclosed=requested_enclosed and (category.code is not null or (c.length_m>=v.length_m and c.width_m>=v.width_m and c.capacity_kg>=v.weight_kg and (not requested_enclosed or c.height_m>=v.height_m)))
   and exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id where f.truck_class_id=c.id and f.region_code=region and d.status='active' and (category.code is null or category.code=any(f.approved_categories)))
   order by case when category.code is not null then c.priority else 0 end,case when category.code is null then c.length_m*c.width_m else 0 end,c.id limit 1;
  if not found then raise exception 'NO_MATCHING_TRUCK'; end if;
  chosen:=t.id;
  select * into price from public.fazaa_tariffs where region_code=region and truck_class_id=chosen and enabled;
  terms:=to_jsonb(price)-'id'-'enabled'||jsonb_build_object('trial_mode',(not s.enabled and public.fazaa_is_trial_customer()),'commission_pct',case when not s.enabled then 0 else s.commission_pct end,'currency_label',s.currency_label,'truck_name',t.name,'vehicle_name',coalesce(description,v.make||' '||v.model),'category_code',category.code,'category_label',category.label,'car_type',coalesce(category.car_type,v.car_type),'enclosed',requested_enclosed);
 end if;
 stops:=p_input->'stops';
 if not public.fazaa_point_ok(pickup) or jsonb_typeof(stops)<>'array' or jsonb_array_length(stops) not between 1 and 4 then raise exception 'INVALID_STOPS'; end if;
 points:=jsonb_build_array(jsonb_build_object('lat',(pickup->>'lat')::numeric,'lng',(pickup->>'lng')::numeric));
 for item in select value from jsonb_array_elements(stops) loop
  if not public.fazaa_point_ok(item) or length(coalesce(item->>'label',''))>120 or (item ? 'unload' and jsonb_typeof(item->'unload')<>'boolean') then raise exception 'INVALID_STOPS'; end if;
  points:=points||jsonb_build_array(jsonb_build_object('lat',(item->>'lat')::numeric,'lng',(item->>'lng')::numeric));
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('lat',(e.value->>'lat')::numeric,'lng',(e.value->>'lng')::numeric,'label',left(coalesce(e.value->>'label','وجهة'),120),'unload',coalesce((e.value->>'unload')::boolean,false)) order by e.ordinality),'[]'::jsonb) into stops from jsonb_array_elements(stops) with ordinality e(value,ordinality);
 if parent is not null then
  -- Append after the already-agreed destinations; do not reroute or reprice earlier legs.
  if jsonb_array_length(current_stops)+jsonb_array_length(stops)>8 then raise exception 'TOO_MANY_STOPS'; end if;
  -- unload flag on first newly added stop requests a new loading/unloading cycle at the old final stop.
  stops:=current_stops||stops;
 end if;
 insert into public.fazaa_fare_quotes(customer_id,region_code,vehicle_id,vehicle_year,truck_class_id,pickup,stops,route_points,terms,parent_request_id,base_version,settings_revision)
 values(auth.uid(),region,v.id,yr,chosen,pickup,stops,points,terms,parent,version,s.revision) returning id into ticket;
 return jsonb_build_object('ticket_id',ticket,'points',points,'trial_mode',(not s.enabled and public.fazaa_is_trial_customer()));
end $$;
create or replace function public.create_fazaa_request(p_quote uuid,p_problem text,p_phone text,p_note text default null,p_payment text default 'cash')
returns uuid language plpgsql security definer set search_path='' as $$
declare q public.fazaa_fare_quotes%rowtype; s public.fazaa_fare_settings%rowtype; v public.fazaa_vehicle_models%rowtype; result uuid;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into s from public.fazaa_fare_settings where id for share;
 select * into q from public.fazaa_fare_quotes where id=p_quote and customer_id=auth.uid() for update;
 if not found or q.parent_request_id is not null then raise exception 'INVALID_QUOTE'; end if;
 if q.request_id is not null then return q.request_id; end if;
 if not (s.enabled or public.fazaa_is_trial_customer()) or q.total is null or q.total<=0 or q.expires_at<=now() or q.settings_revision<>s.revision then raise exception 'QUOTE_EXPIRED'; end if;
 if p_payment<>'cash' then raise exception 'PAYMENT_NOT_AVAILABLE'; end if;
 if p_problem not in ('engine','battery','tire','accident','other') or p_phone !~ '^\+?[0-9]{7,15}$' then raise exception 'INVALID_DETAILS'; end if;
 select * into v from public.fazaa_vehicle_models where id=q.vehicle_id;
 perform set_config('fazaa.booking_quote',q.id::text,true);
 result:=public.create_customer_request_v2((q.pickup->>'lat')::float8,(q.pickup->>'lng')::float8,p_problem,coalesce(q.terms->>'car_type',v.car_type),p_phone,left(case when q.terms->>'category_code' is not null then concat(q.terms->>'category_label',' — ',q.terms->>'vehicle_name',case when q.vehicle_year is not null then ' — '||q.vehicle_year::text else '' end,E'\n',p_note) else p_note end,300),q.region_code,'tow');
 perform set_config('fazaa.booking_quote','',true);
 update public.fazaa_fare_quotes set request_id=result,approved_at=now() where id=q.id;
 return result;
end $$;
create or replace function public.fazaa_driver_can_take(p_request uuid,p_driver uuid default auth.uid())
returns boolean language plpgsql volatile security definer set search_path='' as $$
declare r public.requests%rowtype; fleet public.fazaa_driver_fleet%rowtype; cap numeric; debt numeric; reserved numeric;
begin
 select * into r from public.requests where id=p_request;
 if not found then return false; end if;
 if r.vehicle_category is not null then
  select * into fleet from public.fazaa_driver_fleet where driver_id=p_driver for share;
  if not found or not(r.vehicle_category=any(fleet.approved_categories)) or fleet.region_code<>r.region_code then return false;end if;
  if not exists(select 1 from public.fazaa_truck_classes where id=fleet.truck_class_id and enabled and enclosed=r.requested_enclosed) then return false;end if;
  if not exists(select 1 from public.drivers where id=p_driver and status='active') then return false;end if;
 end if;
 if r.fare_quote_id is null then return true; end if;
 select * into fleet from public.fazaa_driver_fleet where driver_id=p_driver;
 if not found or fleet.truck_class_id<>r.fare_truck_class or fleet.region_code<>r.region_code then return false; end if;
 if not exists(select 1 from public.fazaa_truck_classes where id=fleet.truck_class_id and enabled) then return false; end if;
 if not exists(select 1 from public.drivers where id=p_driver and status='active') then return false; end if;
 select coalesce(fleet.credit_limit,s.credit_limit) into cap from public.fazaa_fare_settings s where s.id;
 if cap is null then return true; end if;
 debt:=public.fazaa_driver_balance(p_driver);
 select coalesce(sum(round(fare_total*(fare_terms->>'commission_pct')::numeric/100,2)),0) into reserved from public.requests where driver_id=p_driver and id<>r.id and status in ('accepted','arrived','in_progress') and fare_quote_id is not null;
 if debt+reserved>=cap then return false; end if;
 return debt+reserved+round(r.fare_total*(r.fare_terms->>'commission_pct')::numeric/100,2)<=cap;
end $$;

create or replace function public.fazaa_category_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare payload jsonb;q public.fazaa_fare_quotes%rowtype;
begin
 if TG_OP='INSERT' then
  if nullif(current_setting('fazaa.booking_quote',true),'') is not null then
   select * into q from public.fazaa_fare_quotes where id=current_setting('fazaa.booking_quote')::uuid and customer_id=auth.uid();
   new.vehicle_category:=q.terms->>'category_code';new.vehicle_description:=q.terms->>'vehicle_name';new.requested_enclosed:=coalesce((q.terms->>'enclosed')::boolean,false);
  elsif nullif(current_setting('fazaa.category_payload',true),'') is not null then
   payload:=current_setting('fazaa.category_payload')::jsonb;
   new.vehicle_category:=payload->>'category_code';new.vehicle_description:=payload->>'vehicle_name';new.requested_enclosed:=(payload->>'enclosed')::boolean;
  else
   new.vehicle_category:=null;new.vehicle_description:=null;new.requested_enclosed:=null;
  end if;
 else
  if row(new.vehicle_category,new.vehicle_description,new.requested_enclosed) is distinct from row(old.vehicle_category,old.vehicle_description,old.requested_enclosed) then raise exception 'VEHICLE_IMMUTABLE';end if;
  if old.vehicle_category is not null and new.driver_id is not null and new.driver_id is distinct from old.driver_id and not public.fazaa_driver_can_take(old.id,new.driver_id) then raise exception 'TRUCK_OR_CREDIT_NOT_ELIGIBLE';end if;
 end if;
 return new;
end $$;
drop trigger if exists fazaa_category_guard on public.requests;
create trigger fazaa_category_guard before insert or update on public.requests for each row execute function public.fazaa_category_guard();
revoke all on function public.fazaa_category_guard() from public,anon,authenticated;

create or replace function public.create_fazaa_category_request(p_lat float8,p_lng float8,p_problem text,p_phone text,p_category text,p_vehicle_name text,p_region_code text,p_enclosed boolean default false,p_year integer default null,p_note text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.fazaa_vehicle_categories%rowtype;result uuid;description text:=btrim(p_vehicle_name);
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if exists(select 1 from public.fazaa_fare_settings where id and enabled) or public.fazaa_is_trial_customer() then raise exception 'FIXED_QUOTE_REQUIRED';end if;
 select * into c from public.fazaa_vehicle_categories where code=p_category;
 if not found then raise exception 'VEHICLE_NOT_APPROVED';end if;
 if description is null or length(description) not between 2 and 100 then raise exception 'INVALID_DETAILS';end if;
 if p_enclosed is null or (p_enclosed and p_year is null) or (p_year is not null and p_year not between 1900 and extract(year from now())::integer+1) then raise exception 'VEHICLE_YEAR_REQUIRED';end if;
 if not exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id join public.fazaa_truck_classes t on t.id=f.truck_class_id where p_category=any(f.approved_categories) and f.region_code=p_region_code and d.status='active' and t.enabled and t.enclosed=p_enclosed) then raise exception 'NO_MATCHING_TRUCK';end if;
 perform set_config('fazaa.category_payload',jsonb_build_object('category_code',p_category,'vehicle_name',description,'enclosed',p_enclosed)::text,true);
 result:=public.create_customer_request_v2(p_lat,p_lng,p_problem,c.car_type,p_phone,left(concat(c.label,' — ',description,case when p_year is not null then ' — '||p_year::text else '' end,E'\n',p_note),300),p_region_code,'tow');
 perform set_config('fazaa.category_payload','',true);
 return result;
end $$;
revoke all on function public.create_fazaa_category_request(float8,float8,text,text,text,text,text,boolean,integer,text) from public,anon;
grant execute on function public.create_fazaa_category_request(float8,float8,text,text,text,text,text,boolean,integer,text) to authenticated;
create or replace function public.admin_save_fazaa_commercial(p_kind text,p_values jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare ident uuid; setting public.fazaa_fare_settings%rowtype; field text; value text;
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into setting from public.fazaa_fare_settings where id for update;
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
notify pgrst,'reload schema';
commit;
