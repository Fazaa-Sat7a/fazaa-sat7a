-- Disposable CI database only.
do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable test database required';end if;end $$;
select set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',false);
select public.admin_save_fazaa_commercial('settings','{"enabled":true,"commission_pct":0,"credit_limit":null,"settlement_days":7,"currency_label":"TEST"}');
update auth.users set email=null,email_confirmed_at=null where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
select set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated","is_anonymous":true}',false);
do $$ declare q uuid;r uuid;before_total numeric;begin
 perform public.test_assert((public.get_fazaa_commercial_catalog()->>'enabled')::boolean,'guest receives full booking when public pricing enabled');
 perform public.test_assert(not exists(select 1 from public.get_customer_history(50,0) where status in ('done','expired','cancelled_customer','cancelled_driver')),'guest cannot list historical orders');
 q:=(public.prepare_fazaa_quote('{"region_code":"damascus","category_code":"passenger","vehicle_name":"Guest test car","enclosed":false,"pickup":{"lat":33.5,"lng":36.2},"stops":[{"lat":33.6,"lng":36.3,"label":"Guest destination"}]}'::jsonb)->>'ticket_id')::uuid;
 before_total:=(public.finish_fazaa_quote(q,3200,600)->>'total')::numeric;
 r:=public.create_fazaa_request(q,'engine','0999999999');
 perform public.test_assert(exists(select 1 from public.get_customer_history(50,0) where id=r),'guest can recover active order');
 perform public.test_assert((public.get_fazaa_trip_details(r)->>'total')::numeric=before_total,'guest gets fixed price and destination receipt');
 perform set_config('request.jwt.claims','{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}',false);
 perform public.test_assert(public.driver_accept_request(r),'approved driver accepts guest booking');
 update public.requests set status='done',done_at=now() where id=r;
 perform set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated","is_anonymous":true}',false);
 perform public.test_assert(not exists(select 1 from public.get_customer_history(50,0) where id=r),'completed guest order absent from history');
 perform public.test_assert(exists(select 1 from public.get_customer_request(r)),'current receipt remains accessible after completion');
 perform public.rate_customer_request(r,4,'Guest review remains private');
 update auth.users set email='customer@example.test',email_confirmed_at=now() where id=auth.uid();
 perform public.test_assert(not exists(select 1 from public.get_customer_history(50,0) where id=r),'anonymous claim cannot unlock history even with confirmed email');
 perform set_config('request.jwt.claims','{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated","is_anonymous":false}',false);
 perform public.test_assert(exists(select 1 from public.get_customer_history(50,0) where id=r),'confirmed upgraded account sees former guest order without changing ownership');
 perform set_config('request.jwt.claims','{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated","is_anonymous":false}',false);
 perform public.test_assert(not exists(select 1 from public.get_customer_history(50,0) where id=r),'other account cannot list this order');
end $$;
select 'PASS guest destination/price/booking/tracking/rating; history reserved for confirmed account; ownership preserved';
