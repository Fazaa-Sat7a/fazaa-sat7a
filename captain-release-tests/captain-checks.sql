do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable database required';end if;end $$;
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}',false);
select public.test_assert(exists(select 1 from public.requests r where r.vehicle_category='passenger' and r.fare_quote_id is not null and public.get_fazaa_trip_details(r.id)->>'category_label'='سيارة ركوب' and (public.get_fazaa_trip_details(r.id)->>'enclosed')::boolean=false),'approved category and service included with priced details');
select public.test_assert(public.get_fazaa_trip_details((select id from public.test_ids where key='first')) is not null,'legacy request remains readable');
select set_config('request.jwt.claims','{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}',false);
select public.test_assert(not exists(select 1 from public.requests r where r.customer_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and public.get_fazaa_trip_details(r.id) is not null),'unrelated customer cannot inspect vehicle or fares');
