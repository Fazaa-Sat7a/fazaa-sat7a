-- Read-only offer discovery must not take row locks. Keep assignment locking on writes.
begin;
create or replace function public.fazaa_driver_can_take(p_request uuid,p_driver uuid default auth.uid())
returns boolean language plpgsql stable security definer set search_path='' as $$
declare r public.requests%rowtype; fleet public.fazaa_driver_fleet%rowtype; cap numeric; debt numeric; reserved numeric;
begin
 select * into r from public.requests where id=p_request;
 if not found then return false; end if;
 if r.vehicle_category is not null then
  select * into fleet from public.fazaa_driver_fleet where driver_id=p_driver;
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

create or replace function public.fazaa_lock_assignment_fleet()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.driver_id is not null then
  if TG_OP='INSERT' then
   perform 1 from public.fazaa_driver_fleet where driver_id=new.driver_id for share;
  elsif new.driver_id is distinct from old.driver_id then
   perform 1 from public.fazaa_driver_fleet where driver_id=new.driver_id for share;
  end if;
 end if;
 return new;
end $$;
revoke all on function public.fazaa_lock_assignment_fleet() from public,anon,authenticated;
drop trigger if exists fazaa_00_lock_assignment_fleet on public.requests;
create trigger fazaa_00_lock_assignment_fleet before insert or update on public.requests
for each row execute function public.fazaa_lock_assignment_fleet();
notify pgrst,'reload schema';
commit;
