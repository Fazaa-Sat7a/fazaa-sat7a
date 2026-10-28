-- DISPOSABLE DATABASE ONLY. Never run this file in Supabase production.
do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable test database required';end if;end $$;
update auth.users set email=id::text||'@example.test';
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}',false);
select public.expect_error('select public.admin_get_fazaa_vehicle_suggestions()','ADMIN_REQUIRED');
select public.expect_error('select public.admin_import_fazaa_vehicle_models(''[]'')','ADMIN_REQUIRED');
select public.test_assert(not has_table_privilege('authenticated','public.fazaa_vehicle_suggestions','select'),'suggestions private');
select public.test_assert(not has_table_privilege('authenticated','public.fazaa_vehicle_model_sources','select'),'provenance private');
select public.test_assert(not has_function_privilege('anon','public.submit_fazaa_vehicle_suggestion(text,text,integer)','execute'),'anonymous RPC denied');
set role authenticated;
do $$ declare first_id uuid;i integer;begin
 first_id:=public.submit_fazaa_vehicle_suggestion(' ماركة اختبار ','موديل',2020);
 perform public.test_assert(first_id=public.submit_fazaa_vehicle_suggestion('ماركة اختبار','موديل',2020),'duplicate is idempotent');
 perform public.expect_error('select public.submit_fazaa_vehicle_suggestion('''',''model'',null)','INVALID_VEHICLE');
 for i in 2..10 loop perform public.submit_fazaa_vehicle_suggestion('Test',i::text,null);end loop;
 perform public.expect_error('select public.submit_fazaa_vehicle_suggestion(''Test'',''11'',null)','SUGGESTION_RATE_LIMIT');
end $$;
reset role;
select set_config('request.jwt.claims','{}',false);
select public.expect_error('select public.submit_fazaa_vehicle_suggestion(''Test'',''model'',null)','SIGN_IN_REQUIRED');
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',false);
do $$ declare item jsonb;before_count integer;s uuid;begin
 item:='{"make":"Fixture import","model":"Sedan","car_type":"small","length_m":4.5,"width_m":1.8,"height_m":1.5,"weight_kg":1400,"year_from":2010,"year_to":2025,"source":"TEST ONLY, not real dimensions","enabled":false}';
 perform public.test_assert(public.admin_import_fazaa_vehicle_models(jsonb_build_array(item))=1,'import saves one');
 perform public.admin_import_fazaa_vehicle_models(jsonb_build_array(item));
 perform public.test_assert((select count(*)=1 from public.fazaa_vehicle_models where make='Fixture import'),'rerun updates same model');
 perform public.test_assert((select not enabled from public.fazaa_vehicle_models where make='Fixture import'),'import preserves disabled status');
 select count(*) into before_count from public.fazaa_vehicle_models;
 perform public.expect_error(format('select public.admin_import_fazaa_vehicle_models(%L)',jsonb_build_array(item||'{"model":"Should roll back"}'::jsonb,item||'{"length_m":0}'::jsonb)::text),'INVALID_IMPORT_ROW');
 perform public.test_assert((select count(*)=before_count from public.fazaa_vehicle_models),'invalid second row rolls back first');
 perform public.expect_error('select public.admin_import_fazaa_vehicle_models(''{}'')','INVALID_IMPORT');
 select id into s from public.fazaa_vehicle_suggestions limit 1;
 perform public.admin_review_fazaa_vehicle_suggestion(s,'reviewed');
 perform public.test_assert((select count(*)=before_count from public.fazaa_vehicle_models),'review does not auto-create unverified model');
 perform public.test_assert(jsonb_array_length(public.admin_get_fazaa_vehicle_suggestions())=10,'admin reads suggestions');
 perform public.test_assert((select not enabled from public.fazaa_fare_settings where id),'global pricing stays off');
end $$;
select 'PASS: suggestion privacy, role checks, duplicate/rate limits, atomic verified imports and unchanged pricing';
