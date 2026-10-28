do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable database required';end if;end $$;
-- Previously FOR SHARE failed here even though listing offers only reads data.
begin read only;
select public.test_assert(exists(select 1 from public.requests where vehicle_category is not null),'category fixture must be present');
select public.test_assert(public.fazaa_driver_can_take(r.id,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')=false,'unapproved fleet still excluded') from public.requests r where r.vehicle_category is not null;
select public.fazaa_driver_can_take(r.id,'dddddddd-dddd-4ddd-8ddd-dddddddddddd') from public.requests r where r.vehicle_category is not null;
select set_config('request.jwt.claims','{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}',true);
select * from public.driver_open_requests(15);
commit;
select public.test_assert(exists(select 1 from pg_trigger where tgname='fazaa_00_lock_assignment_fleet'),'assignment locking retained');
