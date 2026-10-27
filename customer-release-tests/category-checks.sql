-- Disposable fixture only. Never run this file on Supabase.
do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable test database required';end if;end $$;
select public.test_assert(not exists(select 1 from public.fazaa_driver_fleet where cardinality(approved_categories)>0),'migration never invents fleet approvals');
select public.test_assert(not has_table_privilege('authenticated','public.fazaa_vehicle_categories','insert'),'customers cannot approve categories');
select public.test_assert(not has_function_privilege('anon','public.create_fazaa_category_request(double precision,double precision,text,text,text,text,text,boolean,integer,text)','execute'),'booking requires authenticated session');
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',false);
-- Previous catalog tests rename fixture emails. Restore this test account explicitly.
update auth.users set email='customer@example.test',email_confirmed_at=coalesce(email_confirmed_at,now()) where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
select public.admin_set_fazaa_trial_customer('customer@example.test',true);
-- Same pricing class, but only the first driver will be approved for passenger vehicles.
select public.admin_save_fazaa_commercial('fleet','{"driver_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","truck_class_id":"11111111-1111-4111-8111-111111111111","region_code":"damascus","approved_categories":["pickup"]}');
select public.expect_error('select public.admin_save_fazaa_commercial(''fleet'',''{"driver_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","approved_categories":["invented"]}'')','INVALID_CATEGORIES');
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}',false);
select public.expect_error('select public.admin_save_fazaa_commercial(''fleet'',''{}'')','ADMIN_REQUIRED');
select public.expect_error('select public.create_fazaa_category_request(33.5,36.2,''engine'',''0999999999'',''passenger'',''Test car'',''damascus'')','FIXED_QUOTE_REQUIRED');
do $$ declare input jsonb:='{"region_code":"damascus","category_code":"passenger","vehicle_name":"تويوتا اختبار","enclosed":false,"pickup":{"lat":33.5,"lng":36.2},"stops":[{"lat":33.6,"lng":36.3,"label":"TEST garage"}]}';q uuid;r uuid;extra uuid;before_total numeric;begin
 perform public.expect_error(format('select public.prepare_fazaa_quote(%L::jsonb)',input),'NO_MATCHING_TRUCK');
 perform public.expect_error(format('select public.prepare_fazaa_quote(%L::jsonb)',jsonb_set(input,'{enclosed}','true')),'VEHICLE_YEAR_REQUIRED');
 perform public.expect_error(format('select public.prepare_fazaa_quote(%L::jsonb)',jsonb_set(input,'{category_code}','"heavy_truck"')),'VEHICLE_NOT_APPROVED');
 perform set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',false);
 perform public.admin_save_fazaa_commercial('fleet','{"driver_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","truck_class_id":"11111111-1111-4111-8111-111111111111","region_code":"damascus","approved_categories":["passenger","suv_large"]}');
 -- Optional documentation dimensions, independent from category suitability.
 perform public.admin_save_fazaa_commercial('class','{"id":"11111111-1111-4111-8111-111111111111","name":"TEST approved","enclosed":false,"length_m":null,"width_m":null,"capacity_kg":null,"height_m":null,"enabled":true,"priority":10}');
 perform set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}',false);
 q:=(public.prepare_fazaa_quote(input)->>'ticket_id')::uuid;
 perform public.test_assert((select vehicle_id is null and terms->>'category_code'='passenger' from public.fazaa_fare_quotes where id=q),'category quotes need no model row');
 before_total:=(public.finish_fazaa_quote(q,3200,600)->>'total')::numeric;
 r:=public.create_fazaa_request(q,'engine','0999999999','private note');
 perform public.test_assert((select vehicle_category='passenger' and vehicle_description='تويوتا اختبار' and position('تويوتا اختبار' in note)>0 from public.requests where id=r),'driver receives description and classification');
 perform public.test_assert(public.create_fazaa_request(q,'engine','0999999999')=r,'category booking remains idempotent');
 perform public.expect_error(format('update public.requests set vehicle_category=''pickup'' where id=%L',r),'VEHICLE_IMMUTABLE');
 perform public.test_assert(not public.fazaa_driver_can_take(r,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),'same class cannot substitute for manual approval');
 perform set_config('request.jwt.claims','{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","role":"authenticated"}',false);
 perform public.test_assert(not exists(select 1 from public.driver_open_requests(15) where id=r),'unapproved driver cannot see category offer');
 perform public.expect_error(format('select public.driver_accept_request(%L)',r),'TRUCK_OR_CREDIT_NOT_ELIGIBLE');
 perform set_config('request.jwt.claims','{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}',false);
 perform public.test_assert(public.driver_accept_request(r),'approved driver can accept');
 perform set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}',false);
 extra:=(public.prepare_fazaa_quote(jsonb_build_object('request_id',r,'stops','[{"lat":33.7,"lng":36.4,"label":"additional"}]'::jsonb))->>'ticket_id')::uuid;
 perform public.finish_fazaa_quote(extra,1000,60);
 perform public.test_assert((select fare_total=before_total from public.requests where id=r),'unapproved extension does not change total');
 perform public.approve_fazaa_extension(extra);
 perform public.test_assert((select fare_total>before_total from public.requests where id=r),'explicit approved extension supports category quote');
 -- Completing does not change agreed total and preserves commission accounting.
 select fare_total into before_total from public.requests where id=r;
 update public.requests set status='done',done_at=now() where id=r;
 perform public.test_assert((select fare_total=before_total from public.requests where id=r),'completion never reprices');
 perform public.test_assert((public.get_fazaa_trip_details(r)->>'vehicle_name')='تويوتا اختبار','receipt retains model description');
end $$;
select public.test_assert(public.get_fazaa_trip_details((select id from public.test_ids where key='first')) is not null,'existing model-based trip remains readable');
-- Public mode retains the public gate; new category requests are also matched by approvals.
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',false);
select public.admin_set_fazaa_trial_customer('customer@example.test',false);
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}',false);
do $$ declare r uuid;begin
 r:=public.create_fazaa_category_request(33.5,36.2,'engine','0999999999','passenger','Test car','damascus');
 perform public.test_assert((select vehicle_category='passenger' and fare_quote_id is null from public.requests where id=r),'public booking uses category with pricing still off');
 perform public.test_assert(not public.fazaa_driver_can_take(r,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'),'public booking also requires approval');
 perform public.test_assert(public.cancel_customer_request(r),'public booking remains cancellable');
end $$;
select public.test_assert((select not enabled from public.fazaa_fare_settings where id),'global pricing remains OFF');
select 'PASS category matching, manual approvals, optional dimensions, private gate, public fallback, fixed totals and legacy records preserved';
