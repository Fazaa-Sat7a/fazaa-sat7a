-- Disposable CI database only; not for live Supabase.
do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable test database required';end if;end $$;
begin;
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated","is_anonymous":true}',true);
do $$ declare input jsonb:='{"region_code":"damascus","category_code":"passenger","vehicle_name":"","enclosed":false,"pickup":{"lat":33.5,"lng":36.2},"stops":[{"lat":33.6,"lng":36.3}]}';q uuid;r uuid;expected numeric;begin
 q:=(public.prepare_fazaa_quote(input)->>'ticket_id')::uuid;
 perform public.test_assert((select vehicle_year is null and terms->>'vehicle_name'='غير محددة' from public.fazaa_fare_quotes where id=q),'optional description and year');
 expected:=(public.finish_fazaa_quote(q,3200,600)->>'total')::numeric;
 r:=public.create_fazaa_request(q,'','0999999999');
 perform public.test_assert((select fare_total=expected and problem='other' from public.requests where id=r),'optional reason defaults safely and fare remains fixed');
 perform public.test_assert(public.cancel_customer_request(r),'guest cancel remains accessible');
 perform public.expect_error(format('select public.prepare_fazaa_quote(%L::jsonb)',input||'{"vehicle_year":1800}'::jsonb),'VEHICLE_YEAR_REQUIRED');
 perform public.expect_error(format('select public.prepare_fazaa_quote(%L::jsonb)',input||'{"category_code":""}'::jsonb),'VEHICLE_NOT_APPROVED');
 -- Enclosed still requires approved matching fleet, but no year or model is required.
 update public.fazaa_truck_classes set enclosed=true where id='11111111-1111-4111-8111-111111111111';
 q:=(public.prepare_fazaa_quote(input||'{"enclosed":true}'::jsonb)->>'ticket_id')::uuid;
 perform public.test_assert((select vehicle_year is null and (terms->>'enclosed')::boolean from public.fazaa_fare_quotes where id=q),'enclosed year optional too');
 perform public.test_assert(not has_table_privilege('authenticated','public.fazaa_place_search_limits','select'),'search counters private');
 for i in 1..40 loop perform public.claim_fazaa_place_search();end loop;
 perform public.expect_error('select public.claim_fazaa_place_search()','SEARCH_LIMIT');
end $$;
rollback;
select 'PASS optional make/model/year/reason, required category, fixed pricing, guest booking and search rate limit';
