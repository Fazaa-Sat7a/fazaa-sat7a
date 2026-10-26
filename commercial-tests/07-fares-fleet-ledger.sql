-- Fazaa v0.3. Additive commercial layer. Apply after migrations 01/03/04/05.
-- Pricing starts DISABLED, no invented rates or vehicle dimensions are inserted.
begin;
create table if not exists public.fazaa_fare_settings (
 id boolean primary key default true check(id), enabled boolean not null default false,
 commission_pct numeric(5,2) not null default 0 check(commission_pct between 0 and 100),
 currency_label text not null default 'ل.س', credit_limit numeric(14,2),
 settlement_days integer not null default 7 check(settlement_days between 1 and 60),
 revision bigint not null default 1,
 check(credit_limit is null or credit_limit>0)
);
insert into public.fazaa_fare_settings(id) values(true) on conflict do nothing;
create table if not exists public.fazaa_truck_classes (
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 80),
 enclosed boolean not null default false,
 length_m numeric(6,2) not null check(length_m>0 and length_m<30),
 width_m numeric(6,2) not null check(width_m>0 and width_m<10),
 capacity_kg numeric(9,2) not null check(capacity_kg>0),
 height_m numeric(6,2), enabled boolean not null default false,
 check(not enclosed or (height_m is not null and height_m>0))
);
create table if not exists public.fazaa_vehicle_models (
 id uuid primary key default gen_random_uuid(), make text not null check(length(make) between 1 and 60),
 model text not null check(length(model) between 1 and 100),
 car_type text not null check(car_type in ('small','suv','truck')),
 length_m numeric(6,2) not null check(length_m>0), width_m numeric(6,2) not null check(width_m>0),
 height_m numeric(6,2) not null check(height_m>0), weight_kg numeric(9,2) not null check(weight_kg>0),
 year_from integer not null check(year_from between 1900 and 2200),
 year_to integer not null check(year_to between year_from and 2200), enabled boolean not null default false
);
create table if not exists public.fazaa_fare_zones (
 region_code text primary key references public.customer_regions(code),
 south numeric not null, west numeric not null, north numeric not null, east numeric not null,
 enabled boolean not null default false,
 check(south>=-90 and north<=90 and south<north and west>=-180 and east<=180 and west<east)
);
create table if not exists public.fazaa_tariffs (
 id uuid primary key default gen_random_uuid(), region_code text not null references public.customer_regions(code),
 truck_class_id uuid not null references public.fazaa_truck_classes(id),
 start_fee numeric(14,2) not null default 0 check(start_fee>=0),
 per_km numeric(14,2) not null default 0 check(per_km>=0),
 per_minute numeric(14,2) not null default 0 check(per_minute>=0),
 loading_fee numeric(14,2) not null default 0 check(loading_fee>=0),
 unloading_fee numeric(14,2) not null default 0 check(unloading_fee>=0),
 minimum_fare numeric(14,2) not null check(minimum_fare>0),
 rounding_unit numeric(12,2) not null default 1 check(rounding_unit>0),
 enabled boolean not null default false, unique(region_code,truck_class_id)
);
create table if not exists public.fazaa_driver_fleet (
 driver_id uuid primary key references public.drivers(id), truck_class_id uuid not null references public.fazaa_truck_classes(id),
 region_code text not null references public.customer_regions(code), credit_limit numeric(14,2),
 check(credit_limit is null or credit_limit>0)
);
create table if not exists public.fazaa_fare_quotes (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references auth.users(id),
 region_code text not null, vehicle_id uuid not null references public.fazaa_vehicle_models(id),
 vehicle_year integer, truck_class_id uuid not null references public.fazaa_truck_classes(id),
 pickup jsonb not null, stops jsonb not null, route_points jsonb not null, terms jsonb not null,
 parent_request_id uuid references public.requests(id), base_version integer not null default 0,
 settings_revision bigint not null, metres numeric, seconds numeric, total numeric(14,2),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '10 minutes',
 request_id uuid references public.requests(id), approved_at timestamptz,
 check(total is null or total>=0)
);
create index if not exists fazaa_quotes_owner_time on public.fazaa_fare_quotes(customer_id,created_at desc);
alter table public.requests add column if not exists fare_quote_id uuid references public.fazaa_fare_quotes(id);
alter table public.requests add column if not exists fare_total numeric(14,2);
alter table public.requests add column if not exists fare_currency text;
alter table public.requests add column if not exists fare_truck_class uuid references public.fazaa_truck_classes(id);
alter table public.requests add column if not exists fare_stops jsonb;
alter table public.requests add column if not exists fare_vehicle_id uuid references public.fazaa_vehicle_models(id);
alter table public.requests add column if not exists fare_vehicle_year integer;
alter table public.requests add column if not exists fare_terms jsonb;
alter table public.requests add column if not exists fare_revision integer not null default 0;
create table if not exists public.fazaa_driver_ledger (
 id uuid primary key default gen_random_uuid(), driver_id uuid not null references public.drivers(id),
 request_id uuid references public.requests(id), kind text not null check(kind in ('commission','settlement','adjustment')),
 amount numeric(14,2) not null, note text not null default '', reference text,
 created_at timestamptz not null default now(), created_by uuid references auth.users(id),
 check(kind<>'commission' or amount>=0), check(kind<>'settlement' or amount<0)
);
create unique index if not exists fazaa_ledger_once_per_trip on public.fazaa_driver_ledger(request_id) where kind='commission';
create unique index if not exists fazaa_ledger_settlement_reference on public.fazaa_driver_ledger(reference) where kind='settlement';
create index if not exists fazaa_ledger_driver_time on public.fazaa_driver_ledger(driver_id,created_at desc);
-- No direct writes from browser or native app; privileged routines enforce invariants.
do $$ declare tab text; begin
 foreach tab in array array['fazaa_fare_settings','fazaa_truck_classes','fazaa_vehicle_models','fazaa_fare_zones','fazaa_tariffs','fazaa_driver_fleet','fazaa_fare_quotes','fazaa_driver_ledger'] loop
  execute format('alter table public.%I enable row level security',tab);
  execute format('revoke all on public.%I from public,anon,authenticated',tab);
 end loop;
end $$;

create or replace function public.fazaa_point_ok(p jsonb)
returns boolean language plpgsql immutable set search_path='' as $$
declare a numeric; b numeric;
begin
 if jsonb_typeof(p) is distinct from 'object' or jsonb_typeof(p->'lat') is distinct from 'number' or jsonb_typeof(p->'lng') is distinct from 'number' then return false; end if;
 a:=(p->>'lat')::numeric; b:=(p->>'lng')::numeric;
 return a between -90 and 90 and b between -180 and 180;
exception when others then return false;
end $$;

create or replace function public.get_fazaa_commercial_catalog()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('enabled',s.enabled,'currency_label',s.currency_label,
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'make',v.make,'model',v.model,'car_type',v.car_type,'year_from',v.year_from,'year_to',v.year_to) order by v.make,v.model) from public.fazaa_vehicle_models v where v.enabled),'[]'::jsonb),
 'matches',coalesce((select jsonb_agg(jsonb_build_object('vehicle_id',v.id,'region_code',p.region_code,'enclosed',c.enclosed,'truck_name',c.name,'length_m',c.length_m) order by c.length_m*c.width_m,c.capacity_kg,c.id)
 from public.fazaa_vehicle_models v join public.fazaa_truck_classes c on c.enabled and c.length_m>=v.length_m and c.width_m>=v.width_m and c.capacity_kg>=v.weight_kg and (not c.enclosed or c.height_m>=v.height_m)
 join public.fazaa_tariffs p on p.truck_class_id=c.id and p.enabled
 where v.enabled and exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id where f.truck_class_id=c.id and f.region_code=p.region_code and d.status='active')),'[]'::jsonb),
 'shamcash_enabled',false) from public.fazaa_fare_settings s where s.id;
$$;

create or replace function public.prepare_fazaa_quote(p_input jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.fazaa_fare_settings%rowtype; v public.fazaa_vehicle_models%rowtype;
 t public.fazaa_truck_classes%rowtype; price public.fazaa_tariffs%rowtype; r public.requests%rowtype;
 zone public.fazaa_fare_zones%rowtype; pickup jsonb; stops jsonb; points jsonb; item jsonb;
 terms jsonb; chosen uuid; region text; yr integer; parent uuid; version integer:=0; ticket uuid;
 enclosed boolean; current_stops jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 perform pg_advisory_xact_lock(hashtextextended('fare-quote:'||auth.uid()::text,0));
 select * into s from public.fazaa_fare_settings where id for share;
 if not s.enabled then raise exception 'PRICING_NOT_READY'; end if;
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
  select * into v from public.fazaa_vehicle_models where id=(p_input->>'vehicle_id')::uuid and enabled;
  if not found then raise exception 'VEHICLE_NOT_APPROVED'; end if;
  enclosed:=coalesce((p_input->>'enclosed')::boolean,false); yr:=nullif(p_input->>'vehicle_year','')::integer;
  if enclosed and (yr is null or yr not between v.year_from and v.year_to) then raise exception 'VEHICLE_YEAR_REQUIRED'; end if;
  if yr is not null and yr not between v.year_from and v.year_to then raise exception 'VEHICLE_YEAR_REQUIRED'; end if;
  select * into zone from public.fazaa_fare_zones where region_code=region and enabled;
  if not found or not public.fazaa_point_ok(pickup) then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  if (pickup->>'lat')::numeric not between zone.south and zone.north or (pickup->>'lng')::numeric not between zone.west and zone.east then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  if not exists(select 1 from public.customer_service_coverage c join public.customer_regions cr on cr.code=c.region_code where c.region_code=region and c.service_code='tow' and c.enabled and cr.enabled) then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  select c.* into t from public.fazaa_truck_classes c join public.fazaa_tariffs p on p.truck_class_id=c.id and p.region_code=region and p.enabled
   where c.enabled and c.enclosed=enclosed and c.length_m>=v.length_m and c.width_m>=v.width_m and c.capacity_kg>=v.weight_kg and (not enclosed or c.height_m>=v.height_m)
   and exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id where f.truck_class_id=c.id and f.region_code=region and d.status='active')
   order by c.length_m*c.width_m,c.capacity_kg,c.id limit 1;
  if not found then raise exception 'NO_MATCHING_TRUCK'; end if;
  chosen:=t.id;
  select * into price from public.fazaa_tariffs where region_code=region and truck_class_id=chosen and enabled;
  terms:=to_jsonb(price)-'id'-'enabled'||jsonb_build_object('commission_pct',s.commission_pct,'currency_label',s.currency_label,'truck_name',t.name,'vehicle_name',v.make||' '||v.model,'enclosed',enclosed);
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
 return jsonb_build_object('ticket_id',ticket,'points',points);
end $$;

create or replace function public.finish_fazaa_quote(p_ticket uuid,p_metres numeric,p_seconds numeric)
returns jsonb language plpgsql security definer set search_path='' as $$
declare q public.fazaa_fare_quotes%rowtype; amount numeric; cycles integer; unit numeric; raw numeric;
begin
 -- This routine is executable ONLY by service_role; routing metrics never come from the customer.
 select * into q from public.fazaa_fare_quotes where id=p_ticket for update;
 if not found or q.expires_at<=now() then raise exception 'QUOTE_EXPIRED'; end if;
 if p_metres is null or p_seconds is null or p_metres::text in ('NaN','Infinity','-Infinity') or p_seconds::text in ('NaN','Infinity','-Infinity') or p_metres not between 1 and 3000000 or p_seconds not between 1 and 604800 then raise exception 'INVALID_ROUTE'; end if;
 if q.total is null then
  if q.parent_request_id is null then
   select count(*) into cycles from jsonb_array_elements(q.stops) with ordinality e(value,n) where n<jsonb_array_length(q.stops) and (value->>'unload')::boolean;
   raw:=(q.terms->>'start_fee')::numeric+(1+cycles)*((q.terms->>'loading_fee')::numeric+(q.terms->>'unloading_fee')::numeric)+p_metres/1000*(q.terms->>'per_km')::numeric+p_seconds/60*(q.terms->>'per_minute')::numeric;
   raw:=greatest(raw,(q.terms->>'minimum_fare')::numeric);
  else
   select count(*) into cycles from jsonb_array_elements(q.stops) with ordinality e(value,n) where n>jsonb_array_length(q.stops)-jsonb_array_length(q.route_points)+1 and (value->>'unload')::boolean;
   raw:=cycles*((q.terms->>'loading_fee')::numeric+(q.terms->>'unloading_fee')::numeric)+p_metres/1000*(q.terms->>'per_km')::numeric+p_seconds/60*(q.terms->>'per_minute')::numeric;
  end if;
  unit:=(q.terms->>'rounding_unit')::numeric; amount:=ceil(raw/unit)*unit;
  update public.fazaa_fare_quotes set metres=p_metres,seconds=p_seconds,total=amount where id=q.id returning * into q;
 end if;
 return jsonb_build_object('quote_id',q.id,'total',q.total,'currency_label',q.terms->>'currency_label','truck_name',q.terms->>'truck_name','vehicle_name',q.terms->>'vehicle_name','distance_km',round(q.metres/1000,2),'minutes',ceil(q.seconds/60),'expires_at',q.expires_at,'is_extension',q.parent_request_id is not null);
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
 if not s.enabled or q.total is null or q.total<=0 or q.expires_at<=now() or q.settings_revision<>s.revision then raise exception 'QUOTE_EXPIRED'; end if;
 if p_payment<>'cash' then raise exception 'PAYMENT_NOT_AVAILABLE'; end if;
 if p_problem not in ('engine','battery','tire','accident','other') or p_phone !~ '^\+?[0-9]{7,15}$' then raise exception 'INVALID_DETAILS'; end if;
 select * into v from public.fazaa_vehicle_models where id=q.vehicle_id;
 perform set_config('fazaa.booking_quote',q.id::text,true);
 result:=public.create_customer_request_v2((q.pickup->>'lat')::float8,(q.pickup->>'lng')::float8,p_problem,v.car_type,p_phone,left(p_note,300),q.region_code,'tow');
 perform set_config('fazaa.booking_quote','',true);
 update public.fazaa_fare_quotes set request_id=result,approved_at=now() where id=q.id;
 return result;
end $$;

create or replace function public.approve_fazaa_extension(p_quote uuid)
returns numeric language plpgsql security definer set search_path='' as $$
declare q public.fazaa_fare_quotes%rowtype; r public.requests%rowtype;
begin
 select * into q from public.fazaa_fare_quotes where id=p_quote and customer_id=auth.uid() for update;
 if not found or q.parent_request_id is null then raise exception 'INVALID_QUOTE'; end if;
 if not public.customer_can_access(q.parent_request_id) then raise exception 'AUTH_REQUIRED'; end if;
 select * into r from public.requests where id=q.parent_request_id for update;
 if q.approved_at is not null then return (select fare_total from public.requests where id=r.id); end if;
 if q.total is null or q.expires_at<=now() or r.status not in ('accepted','arrived','in_progress') or r.fare_revision<>q.base_version then raise exception 'QUOTE_EXPIRED'; end if;
 perform set_config('fazaa.approving_extension',q.id::text,true);
 update public.requests set fare_total=fare_total+q.total,fare_stops=q.stops,fare_revision=fare_revision+1 where id=r.id;
 perform set_config('fazaa.approving_extension','',true);
 update public.fazaa_fare_quotes set approved_at=now(),request_id=r.id where id=q.id;
 return r.fare_total+q.total;
end $$;

create or replace function public.fazaa_driver_balance(p_driver uuid)
returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(amount),0) from public.fazaa_driver_ledger where driver_id=p_driver;
$$;
create or replace function public.fazaa_driver_can_take(p_request uuid,p_driver uuid default auth.uid())
returns boolean language plpgsql volatile security definer set search_path='' as $$
declare r public.requests%rowtype; fleet public.fazaa_driver_fleet%rowtype; cap numeric; debt numeric; reserved numeric;
begin
 select * into r from public.requests where id=p_request;
 if not found then return false; end if;
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

create or replace function public.fazaa_guard_request()
returns trigger language plpgsql security definer set search_path='' as $$
declare q public.fazaa_fare_quotes%rowtype; extension public.fazaa_fare_quotes%rowtype;
begin
 if TG_OP='INSERT' then
  if coalesce(current_setting('fazaa.booking_quote',true),'')<>'' then
   select * into q from public.fazaa_fare_quotes where id=current_setting('fazaa.booking_quote')::uuid and customer_id=new.customer_id and customer_id=auth.uid();
   if not found or q.total is null or q.parent_request_id is not null or q.request_id is not null then raise exception 'INVALID_QUOTE'; end if;
   if new.lat<>(q.pickup->>'lat')::float8 or new.lng<>(q.pickup->>'lng')::float8 then raise exception 'INVALID_QUOTE'; end if;
   new.region_code:=q.region_code;new.service_code:='tow';
   new.fare_quote_id:=q.id;new.fare_total:=q.total;new.fare_currency:=q.terms->>'currency_label';new.fare_truck_class:=q.truck_class_id;
   new.fare_vehicle_id:=q.vehicle_id;new.fare_vehicle_year:=q.vehicle_year;new.fare_stops:=q.stops;new.fare_terms:=q.terms;new.fare_revision:=1;
  elsif exists(select 1 from public.fazaa_fare_settings where id and enabled) then raise exception 'FIXED_QUOTE_REQUIRED';
  elsif new.fare_quote_id is not null or new.fare_total is not null then raise exception 'FIXED_QUOTE_REQUIRED';
  end if;
 else
  if old.fare_quote_id is null and row(new.fare_quote_id,new.fare_total,new.fare_terms) is distinct from row(old.fare_quote_id,old.fare_total,old.fare_terms) then raise exception 'FARE_IMMUTABLE'; end if;
  if row(new.fare_quote_id,new.fare_currency,new.fare_truck_class,new.fare_vehicle_id,new.fare_vehicle_year,new.fare_terms,new.lat,new.lng,new.region_code,new.customer_id) is distinct from row(old.fare_quote_id,old.fare_currency,old.fare_truck_class,old.fare_vehicle_id,old.fare_vehicle_year,old.fare_terms,old.lat,old.lng,old.region_code,old.customer_id) and old.fare_quote_id is not null then raise exception 'FARE_IMMUTABLE'; end if;
  if row(new.fare_total,new.fare_stops,new.fare_revision) is distinct from row(old.fare_total,old.fare_stops,old.fare_revision) and old.fare_quote_id is not null then
   select * into extension from public.fazaa_fare_quotes where id=nullif(current_setting('fazaa.approving_extension',true),'')::uuid and parent_request_id=old.id and base_version=old.fare_revision and approved_at is null and expires_at>now() and total is not null;
   if not found or not public.customer_can_access(old.id) or new.fare_total<>old.fare_total+extension.total or new.fare_stops<>extension.stops or new.fare_revision<>old.fare_revision+1 then raise exception 'FARE_IMMUTABLE'; end if;
  end if;
  if old.status='done' and (new.status<>'done' or new.driver_id is distinct from old.driver_id) and old.fare_quote_id is not null then raise exception 'COMPLETED_REQUEST_IMMUTABLE'; end if;
 end if;
 if new.driver_id is not null and new.fare_quote_id is not null and (TG_OP='INSERT' or new.driver_id is distinct from old.driver_id) then
  perform pg_advisory_xact_lock(hashtextextended('fare-driver:'||new.driver_id::text,0));
  if not public.fazaa_driver_can_take(new.id,new.driver_id) then raise exception 'TRUCK_OR_CREDIT_NOT_ELIGIBLE'; end if;
 end if;
 return new;
end $$;
drop trigger if exists fazaa_guard_request on public.requests;
create trigger fazaa_guard_request before insert or update on public.requests for each row execute function public.fazaa_guard_request();

create or replace function public.fazaa_accrue_commission()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='done' and old.status is distinct from 'done' and new.fare_quote_id is not null and new.driver_id is not null then
  insert into public.fazaa_driver_ledger(driver_id,request_id,kind,amount,note)
  values(new.driver_id,new.id,'commission',round(new.fare_total*(new.fare_terms->>'commission_pct')::numeric/100,2),'عمولة رحلة مكتملة') on conflict(request_id) where kind='commission' do nothing;
 end if;
 return new;
end $$;
drop trigger if exists fazaa_accrue_commission on public.requests;
create trigger fazaa_accrue_commission after update of status on public.requests for each row execute function public.fazaa_accrue_commission();

-- Preserve original filtering/expiration/distance logic and return shape for the native driver app.
-- Wrap the existing function dynamically; do not guess its radius type or return schema.
do $$ declare proc record; original oid; begin
 select p.oid into original from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fazaa_legacy_driver_open_requests';
 if original is null then
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='driver_open_requests')<>1 then raise exception 'Expected one driver_open_requests function'; end if;
  select p.oid,pg_get_function_identity_arguments(p.oid) identity_args into proc from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='driver_open_requests';
  execute format('alter function public.driver_open_requests(%s) rename to fazaa_legacy_driver_open_requests',proc.identity_args);
  original:=proc.oid;
 end if;
 select pg_get_function_arguments(original) args,pg_get_function_result(original) result,pg_get_function_identity_arguments(original) identity_args into proc;
 if (select pronargs from pg_proc where oid=original)<>1 then raise exception 'Expected one radius parameter'; end if;
 execute format('create or replace function public.driver_open_requests(%s) returns %s language sql stable security definer set search_path='''' as $body$ select legacy.* from public.fazaa_legacy_driver_open_requests($1) legacy where public.fazaa_driver_can_take(legacy.id,auth.uid()) $body$',proc.args,proc.result);
 execute format('revoke all on function public.fazaa_legacy_driver_open_requests(%s) from public,anon,authenticated',proc.identity_args);
 execute format('revoke all on function public.driver_open_requests(%s) from public,anon',proc.identity_args);
 execute format('grant execute on function public.driver_open_requests(%s) to authenticated',proc.identity_args);
end $$;

create or replace function public.get_fazaa_trip_details(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.requests%rowtype; own_driver boolean; admin boolean;
begin
 select * into r from public.requests where id=p_id;
 if not found then return null; end if;
 admin:=coalesce(public.is_admin(),false);own_driver:=coalesce(r.driver_id=auth.uid(),false);
 if not (admin or public.customer_can_access(r.id) or own_driver or (r.status='new' and r.created_at>now()-interval '15 minutes' and exists(select 1 from public.drivers where id=auth.uid() and status='active' and is_available) and exists(select 1 from public.driver_open_requests(15) offered where offered.id=r.id))) then return null; end if;
 return jsonb_build_object('request_id',r.id,'priced',r.fare_quote_id is not null,'total',r.fare_total,'currency_label',r.fare_currency,'vehicle_name',r.fare_terms->>'vehicle_name','truck_name',r.fare_terms->>'truck_name','stops',r.fare_stops,'version',r.fare_revision,
 'commission_pct',case when admin or own_driver or exists(select 1 from public.drivers where id=auth.uid() and status='active') then (r.fare_terms->>'commission_pct')::numeric end,
 'commission',case when admin or own_driver or exists(select 1 from public.drivers where id=auth.uid() and status='active') then round(r.fare_total*(r.fare_terms->>'commission_pct')::numeric/100,2) end,
 'driver_rating',case when r.driver_id is not null then (select jsonb_build_object('average',round(avg(stars),1),'count',count(*)) from public.ratings where driver_id=r.driver_id) end,
 'can_extend',r.fare_quote_id is not null and r.status in ('accepted','arrived','in_progress') and public.customer_can_access(r.id));
end $$;

create or replace function public.get_fazaa_driver_finances()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.drivers where id=auth.uid()) then raise exception 'DRIVER_REQUIRED'; end if;
 return jsonb_build_object('balance',public.fazaa_driver_balance(auth.uid()),'commission_pct',(select commission_pct from public.fazaa_fare_settings where id),'currency_label',(select currency_label from public.fazaa_fare_settings where id),
 'settlement_days',(select settlement_days from public.fazaa_fare_settings where id),
 'rating',(select jsonb_build_object('average',round(avg(stars),1),'count',count(*)) from public.ratings where driver_id=auth.uid()),
 'ledger',coalesce((select jsonb_agg(to_jsonb(x)) from (select kind,amount,note,reference,created_at from public.fazaa_driver_ledger where driver_id=auth.uid() order by created_at desc limit 100)x),'[]'::jsonb));
end $$;

-- Comments are private to the administrator. Driver/customer stats are aggregate-only RPCs.
revoke select on public.ratings from public,anon;
alter table public.ratings enable row level security;
drop policy if exists fazaa_private_rating_comments on public.ratings;
create policy fazaa_private_rating_comments on public.ratings as restrictive for select to authenticated using(public.is_admin());

create or replace function public.admin_get_fazaa_commercial()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 return jsonb_build_object('settings',(select to_jsonb(s) from public.fazaa_fare_settings s where id),
 'classes',coalesce((select jsonb_agg(to_jsonb(c) order by name) from public.fazaa_truck_classes c),'[]'::jsonb),
 'vehicles',coalesce((select jsonb_agg(to_jsonb(v) order by make,model) from public.fazaa_vehicle_models v),'[]'::jsonb),
 'zones',coalesce((select jsonb_agg(to_jsonb(z)) from public.fazaa_fare_zones z),'[]'::jsonb),
 'tariffs',coalesce((select jsonb_agg(to_jsonb(t)) from public.fazaa_tariffs t),'[]'::jsonb),
 'fleet',coalesce((select jsonb_agg(to_jsonb(f)||jsonb_build_object('name',d.name,'balance',public.fazaa_driver_balance(d.id))) from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id),'[]'::jsonb),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'plate',plate)) from public.drivers),'[]'::jsonb),
 'regions',(select jsonb_agg(jsonb_build_object('code',code,'name',name)) from public.customer_regions),
 'ledger',coalesce((select jsonb_agg(to_jsonb(x)) from (select l.*,d.name from public.fazaa_driver_ledger l join public.drivers d on d.id=l.driver_id order by l.created_at desc limit 100)x),'[]'::jsonb));
end $$;

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
  if (p_values->>'enabled')::boolean and (not exists(select 1 from public.fazaa_vehicle_models where enabled) or not exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id where d.status='active')) then raise exception 'CONFIGURATION_INCOMPLETE'; end if;
  update public.fazaa_fare_settings set enabled=(p_values->>'enabled')::boolean,commission_pct=(p_values->>'commission_pct')::numeric,currency_label=p_values->>'currency_label',credit_limit=nullif(p_values->>'credit_limit','')::numeric,settlement_days=(p_values->>'settlement_days')::integer where id;
 elsif p_kind='class' then
  ident:=coalesce(nullif(p_values->>'id','')::uuid,gen_random_uuid());
  insert into public.fazaa_truck_classes(id,name,enclosed,length_m,width_m,capacity_kg,height_m,enabled) values(ident,p_values->>'name',(p_values->>'enclosed')::boolean,(p_values->>'length_m')::numeric,(p_values->>'width_m')::numeric,(p_values->>'capacity_kg')::numeric,nullif(p_values->>'height_m','')::numeric,(p_values->>'enabled')::boolean)
  on conflict(id) do update set name=excluded.name,enclosed=excluded.enclosed,length_m=excluded.length_m,width_m=excluded.width_m,capacity_kg=excluded.capacity_kg,height_m=excluded.height_m,enabled=excluded.enabled;
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
  insert into public.fazaa_driver_fleet(driver_id,truck_class_id,region_code,credit_limit) values((p_values->>'driver_id')::uuid,(p_values->>'truck_class_id')::uuid,p_values->>'region_code',nullif(p_values->>'credit_limit','')::numeric)
  on conflict(driver_id) do update set truck_class_id=excluded.truck_class_id,region_code=excluded.region_code,credit_limit=excluded.credit_limit;
 else raise exception 'INVALID_KIND'; end if;
 update public.fazaa_fare_settings set revision=revision+1 where id;
end $$;

create or replace function public.admin_record_fazaa_settlement(p_driver uuid,p_amount numeric,p_reference text,p_note text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; existing public.fazaa_driver_ledger%rowtype;
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
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

create or replace function public.get_fazaa_driver_cards(p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:='{}'::jsonb; ident uuid; detail jsonb;
begin
 if not exists(select 1 from public.drivers where id=auth.uid() and status='active') then raise exception 'DRIVER_REQUIRED'; end if;
 if coalesce(array_length(p_ids,1),0)>50 then raise exception 'TOO_MANY_REQUESTS'; end if;
 foreach ident in array coalesce(p_ids,array[]::uuid[]) loop
  detail:=public.get_fazaa_trip_details(ident);
  if detail is not null then result:=result||jsonb_build_object(ident::text,detail); end if;
 end loop;
 return result;
end $$;

-- All routines are private by default; grant only their intended entry points.
do $$ declare p record; begin
 for p in select pr.oid::regprocedure signature from pg_proc pr join pg_namespace n on n.oid=pr.pronamespace where n.nspname='public' and (pr.proname like 'fazaa_%' or pr.proname in ('get_fazaa_commercial_catalog','prepare_fazaa_quote','finish_fazaa_quote','create_fazaa_request','approve_fazaa_extension','get_fazaa_trip_details','get_fazaa_driver_finances','get_fazaa_driver_cards','admin_get_fazaa_commercial','admin_save_fazaa_commercial','admin_record_fazaa_settlement')) loop
  execute format('revoke all on function %s from public,anon,authenticated',p.signature);
 end loop;
end $$;
grant execute on function public.get_fazaa_commercial_catalog() to anon,authenticated;
grant execute on function public.prepare_fazaa_quote(jsonb),public.create_fazaa_request(uuid,text,text,text,text),public.approve_fazaa_extension(uuid),public.get_fazaa_trip_details(uuid),public.get_fazaa_driver_finances(),public.admin_get_fazaa_commercial(),public.admin_save_fazaa_commercial(text,jsonb),public.admin_record_fazaa_settlement(uuid,numeric,text,text) to authenticated;
grant execute on function public.get_fazaa_driver_cards(uuid[]) to authenticated;
grant execute on function public.finish_fazaa_quote(uuid,numeric,numeric) to service_role;
notify pgrst,'reload schema';
commit;
