-- Fazaa 0.5.1: guest booking/tracking unchanged; past history requires confirmed account.
-- Does not change prices, commission, pricing activation or existing requests.
begin;
create or replace function public.get_customer_history(p_limit integer default 20,p_offset integer default 0)
returns table(id uuid,short_code text,status text,problem text,car_type text,customer_phone text,created_at timestamptz,
 region_code text,region_name text,service_code text,service_name text,has_rating boolean)
language sql stable security definer set search_path = '' as $$
 select r.id,r.short_code,
  case when r.status='new' and r.created_at < now()-interval '15 minutes' then 'expired' else r.status end,
  r.problem,r.car_type,r.customer_phone,r.created_at,r.region_code,coalesce(c.name,r.region_code),r.service_code,coalesce(s.name,'سطحة ونقل سيارة'),
  exists(select 1 from public.ratings t where t.request_id=r.id)
 from public.requests r left join public.customer_regions c on c.code=r.region_code left join public.customer_services s on s.code=r.service_code
 where auth.uid() is not null and public.customer_can_access(r.id)
 and (
  (not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
   and exists(select 1 from auth.users u where u.id=auth.uid() and nullif(u.email,'') is not null and u.email_confirmed_at is not null))
  or r.status in ('accepted','arrived','in_progress')
  or (r.status='new' and r.created_at>=now()-interval '15 minutes')
 )
 order by r.created_at desc,r.id desc limit least(greatest(p_limit,1),50) offset greatest(p_offset,0);
$$;
revoke all on function public.get_customer_history(integer,integer) from public,anon;
grant execute on function public.get_customer_history(integer,integer) to authenticated;
notify pgrst,'reload schema';
commit;
