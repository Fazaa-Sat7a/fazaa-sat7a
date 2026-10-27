-- Apply after customer migration 10. Pricing, ownership and dispatch unchanged.
begin;
create or replace function public.get_fazaa_trip_details(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.requests%rowtype; own_driver boolean; admin boolean;
begin
 select * into r from public.requests where id=p_id;
 if not found then return null; end if;
 admin:=coalesce(public.is_admin(),false);own_driver:=coalesce(r.driver_id=auth.uid(),false);
 if not (admin or public.customer_can_access(r.id) or own_driver or (r.status='new' and r.created_at>now()-interval '15 minutes' and exists(select 1 from public.drivers where id=auth.uid() and status='active' and is_available) and exists(select 1 from public.driver_open_requests(15) offered where offered.id=r.id))) then return null; end if;
 return jsonb_build_object('request_id',r.id,'priced',r.fare_quote_id is not null,'total',r.fare_total,'currency_label',r.fare_currency,'category_label',r.fare_terms->>'category_label','enclosed',r.requested_enclosed,'vehicle_year',r.fare_vehicle_year,'vehicle_name',r.fare_terms->>'vehicle_name','truck_name',r.fare_terms->>'truck_name','stops',r.fare_stops,'version',r.fare_revision,
 'commission_pct',case when admin or own_driver or exists(select 1 from public.drivers where id=auth.uid() and status='active') then (r.fare_terms->>'commission_pct')::numeric end,
 'commission',case when admin or own_driver or exists(select 1 from public.drivers where id=auth.uid() and status='active') then round(r.fare_total*(r.fare_terms->>'commission_pct')::numeric/100,2) end,
 'driver_rating',case when r.driver_id is not null then (select jsonb_build_object('average',round(avg(stars),1),'count',count(*)) from public.ratings where driver_id=r.driver_id) end,
 'can_extend',r.fare_quote_id is not null and r.status in ('accepted','arrived','in_progress') and public.customer_can_access(r.id));
end $$;
notify pgrst,'reload schema';
commit;
