-- Add-on AFTER commercial migration 07. No public pricing activation and no sample fleet/rates.
begin;
create table if not exists public.fazaa_trial_customers (
 user_id uuid primary key references auth.users(id) on delete cascade,
 enabled boolean not null default true,
 granted_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
alter table public.fazaa_trial_customers enable row level security;
revoke all on public.fazaa_trial_customers from public,anon,authenticated;
create or replace function public.fazaa_is_trial_customer()
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.fazaa_trial_customers where user_id=auth.uid() and enabled);
$$;
revoke all on function public.fazaa_is_trial_customer() from public,anon,authenticated;
create or replace function public.admin_set_fazaa_trial_customer(p_email text,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare chosen uuid; matches integer;
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if p_enabled is null or length(trim(coalesce(p_email,''))) not between 3 and 254 then raise exception 'INVALID_EMAIL';end if;
 select count(*),(array_agg(u.id))[1] into matches,chosen from auth.users u where lower(u.email)=lower(trim(p_email)) and u.email_confirmed_at is not null;
 if matches<>1 then raise exception 'ONE_CONFIRMED_ACCOUNT_REQUIRED';end if;
 insert into public.fazaa_trial_customers(user_id,enabled,granted_by) values(chosen,p_enabled,auth.uid())
 on conflict(user_id) do update set enabled=excluded.enabled,granted_by=excluded.granted_by,updated_at=now();
end $$;
create or replace function public.admin_get_fazaa_trial_customers()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('email',u.email,'enabled',t.enabled)) from public.fazaa_trial_customers t join auth.users u on u.id=t.user_id),'[]'::jsonb);
end $$;
revoke all on function public.admin_set_fazaa_trial_customer(text,boolean),public.admin_get_fazaa_trial_customers() from public,anon;
grant execute on function public.admin_set_fazaa_trial_customer(text,boolean),public.admin_get_fazaa_trial_customers() to authenticated;
create or replace function public.get_fazaa_commercial_catalog()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('enabled',(s.enabled or public.fazaa_is_trial_customer()),'trial_mode',(not s.enabled and public.fazaa_is_trial_customer()),'currency_label',s.currency_label,
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
 requested_enclosed boolean; current_stops jsonb;
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
  select * into v from public.fazaa_vehicle_models where id=(p_input->>'vehicle_id')::uuid and enabled;
  if not found then raise exception 'VEHICLE_NOT_APPROVED'; end if;
  requested_enclosed:=coalesce((p_input->>'enclosed')::boolean,false); yr:=nullif(p_input->>'vehicle_year','')::integer;
  if requested_enclosed and (yr is null or yr not between v.year_from and v.year_to) then raise exception 'VEHICLE_YEAR_REQUIRED'; end if;
  if yr is not null and yr not between v.year_from and v.year_to then raise exception 'VEHICLE_YEAR_REQUIRED'; end if;
  select * into zone from public.fazaa_fare_zones where region_code=region and enabled;
  if not found or not public.fazaa_point_ok(pickup) then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  if (pickup->>'lat')::numeric not between zone.south and zone.north or (pickup->>'lng')::numeric not between zone.west and zone.east then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  if not exists(select 1 from public.customer_service_coverage c join public.customer_regions cr on cr.code=c.region_code where c.region_code=region and c.service_code='tow' and c.enabled and cr.enabled) then raise exception 'OUTSIDE_SERVICE_AREA'; end if;
  select c.* into t from public.fazaa_truck_classes c join public.fazaa_tariffs p on p.truck_class_id=c.id and p.region_code=region and p.enabled
   where c.enabled and c.enclosed=requested_enclosed and c.length_m>=v.length_m and c.width_m>=v.width_m and c.capacity_kg>=v.weight_kg and (not requested_enclosed or c.height_m>=v.height_m)
   and exists(select 1 from public.fazaa_driver_fleet f join public.drivers d on d.id=f.driver_id where f.truck_class_id=c.id and f.region_code=region and d.status='active')
   order by c.length_m*c.width_m,c.capacity_kg,c.id limit 1;
  if not found then raise exception 'NO_MATCHING_TRUCK'; end if;
  chosen:=t.id;
  select * into price from public.fazaa_tariffs where region_code=region and truck_class_id=chosen and enabled;
  terms:=to_jsonb(price)-'id'-'enabled'||jsonb_build_object('trial_mode',(not s.enabled and public.fazaa_is_trial_customer()),'commission_pct',case when not s.enabled then 0 else s.commission_pct end,'currency_label',s.currency_label,'truck_name',t.name,'vehicle_name',v.make||' '||v.model,'enclosed',requested_enclosed);
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
 result:=public.create_customer_request_v2((q.pickup->>'lat')::float8,(q.pickup->>'lng')::float8,p_problem,v.car_type,p_phone,left(p_note,300),q.region_code,'tow');
 perform set_config('fazaa.booking_quote','',true);
 update public.fazaa_fare_quotes set request_id=result,approved_at=now() where id=q.id;
 return result;
end $$;


notify pgrst,'reload schema';
commit;
