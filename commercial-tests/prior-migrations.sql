-- DISPOSABLE CI DATABASE ONLY. Never run against Supabase.
do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable test database required'; end if; end $$;
-- Fazaa customer app / web handoff v1. Additive migration: old RPCs stay intact.
-- Run the whole file once in Supabase SQL Editor as the project owner.
begin;

create table if not exists public.customer_request_grants (
  request_id uuid not null references public.requests(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days',
  primary key (request_id, user_id)
);
create table if not exists public.customer_request_handoffs (
  request_id uuid primary key references public.requests(id) on delete cascade,
  token_hash text not null unique,
  issued_by uuid not null references auth.users(id) on delete cascade,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  used_by uuid references auth.users(id) on delete set null
);
create table if not exists public.customer_handoff_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null default now(),
  attempts integer not null default 0
);

alter table public.customer_request_grants enable row level security;
alter table public.customer_request_handoffs enable row level security;
alter table public.customer_handoff_attempts enable row level security;
revoke all on table public.customer_request_grants, public.customer_request_handoffs, public.customer_handoff_attempts from public, anon, authenticated;

create or replace function public.customer_can_access(p_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    exists (select 1 from public.requests r where r.id = p_id and r.customer_id = auth.uid())
    or exists (select 1 from public.customer_request_grants g where g.request_id = p_id and g.user_id = auth.uid() and g.expires_at > now())
  );
$$;

create or replace function public.get_customer_request(p_id uuid)
returns table (
  id uuid, status text, problem text, car_type text, lat float8, lng float8,
  short_code text, created_at timestamptz,
  driver_name text, driver_phone text, driver_plate text, driver_truck_type text,
  driver_lat float8, driver_lng float8, driver_location_at timestamptz,
  has_rating boolean, can_share boolean
)
language sql stable security definer set search_path = '' as $$
  select r.id,
    case when r.status = 'new' and r.created_at < now() - interval '15 minutes' then 'expired' else r.status end,
    r.problem, r.car_type, r.lat, r.lng, r.short_code, r.created_at,
    case when r.status in ('accepted','arrived','in_progress') then d.name end,
    case when r.status in ('accepted','arrived','in_progress') then d.phone end,
    case when r.status in ('accepted','arrived','in_progress') then d.plate end,
    case when r.status in ('accepted','arrived','in_progress') then d.truck_type end,
    case when r.status in ('accepted','arrived','in_progress') then d.lat end,
    case when r.status in ('accepted','arrived','in_progress') then d.lng end,
    case when r.status in ('accepted','arrived','in_progress') then d.location_updated_at end,
    exists (select 1 from public.ratings t where t.request_id = r.id),
    r.customer_id = auth.uid()
  from public.requests r left join public.drivers d on d.id = r.driver_id
  where r.id = p_id and public.customer_can_access(r.id);
$$;

create or replace function public.create_customer_request(
  p_lat float8, p_lng float8, p_problem text, p_car_type text, p_phone text, p_note text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  -- A restored active request must not disappear behind a newly created request.
  if exists (
    select 1 from public.requests r join public.customer_request_grants g on g.request_id = r.id
    where g.user_id = auth.uid() and g.expires_at > now()
      and (r.status in ('accepted','arrived','in_progress') or (r.status = 'new' and r.created_at > now() - interval '15 minutes'))
  ) then raise exception 'active request exists'; end if;
  return public.create_request(p_lat, p_lng, p_problem, p_car_type, p_phone, p_note);
end;
$$;

create or replace function public.cancel_customer_request(p_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare affected integer;
begin
  if not public.customer_can_access(p_id) then return false; end if;
  update public.requests set status = 'cancelled_customer', cancelled_at = now()
  where id = p_id and status in ('new','accepted');
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.rate_customer_request(p_id uuid, p_stars integer, p_comment text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare target_driver uuid;
begin
  if not public.customer_can_access(p_id) then raise exception 'cannot rate this request'; end if;
  select r.driver_id into target_driver from public.requests r where r.id = p_id and r.status = 'done';
  if target_driver is null then raise exception 'cannot rate this request'; end if;
  if p_stars is null or p_stars not between 1 and 5 then raise exception 'invalid rating'; end if;
  insert into public.ratings(request_id, driver_id, stars, comment) values (p_id, target_driver, p_stars, left(p_comment,300));
end;
$$;

create or replace function public.issue_customer_handoff(p_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare secret text; code text; expiry timestamptz;
begin
  -- Only the original browser/device owner can generate a handoff secret.
  select r.short_code into code from public.requests r where r.id = p_id and r.customer_id = auth.uid();
  if code is null then raise exception 'handoff not permitted'; end if;
  secret := replace(gen_random_uuid()::text, '-', '');
  expiry := now() + interval '10 minutes';
  insert into public.customer_request_handoffs(request_id, token_hash, issued_by, issued_at, expires_at, used_at, used_by)
  values (p_id, encode(sha256(convert_to(secret,'UTF8')),'hex'), auth.uid(), now(), expiry, null, null)
  on conflict(request_id) do update set token_hash = excluded.token_hash, issued_by = excluded.issued_by,
    issued_at = excluded.issued_at, expires_at = excluded.expires_at, used_at = null, used_by = null;
  return jsonb_build_object('token',secret,'short_code',code,'expires_at',expiry);
end;
$$;

create or replace function public.redeem_customer_handoff(p_short_code text, p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := auth.uid(); count_attempts integer; token text;
  handoff public.customer_request_handoffs%rowtype; code text;
begin
  if caller is null then raise exception 'not authenticated'; end if;
  perform pg_advisory_xact_lock(hashtextextended(caller::text, 0));
  insert into public.customer_handoff_attempts(user_id, window_start, attempts) values (caller,now(),1)
  on conflict(user_id) do update set
    attempts = case when public.customer_handoff_attempts.window_start < now() - interval '15 minutes' then 1 else public.customer_handoff_attempts.attempts + 1 end,
    window_start = case when public.customer_handoff_attempts.window_start < now() - interval '15 minutes' then now() else public.customer_handoff_attempts.window_start end
  returning attempts into count_attempts;
  -- Return failures instead of raising, so attempt counts are not rolled back.
  if count_attempts > 10 then return jsonb_build_object('ok',false,'reason','rate_limit'); end if;
  token := lower(regexp_replace(coalesce(p_token,''), '[^0-9a-fA-F]', '', 'g'));
  if token !~ '^[0-9a-f]{32}$' or coalesce(p_short_code,'') !~ '^[0-9]{6}$' then
    return jsonb_build_object('ok',false,'reason','invalid_code');
  end if;
  select h.* into handoff from public.customer_request_handoffs h
    where h.token_hash = encode(sha256(convert_to(token,'UTF8')),'hex') for update;
  if not found or handoff.expires_at <= now() then
    return jsonb_build_object('ok',false,'reason','invalid_code');
  end if;
  select r.short_code into code from public.requests r where r.id = handoff.request_id and r.customer_id = handoff.issued_by;
  if code is distinct from p_short_code then return jsonb_build_object('ok',false,'reason','invalid_code'); end if;
  -- Retrying after a lost response is safe for the SAME authenticated recipient.
  if handoff.used_at is not null then
    if handoff.used_by = caller and public.customer_can_access(handoff.request_id) then
      return jsonb_build_object('ok',true,'request_id',handoff.request_id);
    end if;
    return jsonb_build_object('ok',false,'reason','invalid_code');
  end if;
  if exists (
    select 1 from public.requests r where r.id <> handoff.request_id and public.customer_can_access(r.id)
      and (r.status in ('accepted','arrived','in_progress') or (r.status = 'new' and r.created_at > now() - interval '15 minutes'))
  ) then return jsonb_build_object('ok',false,'reason','active_request'); end if;
  insert into public.customer_request_grants(request_id,user_id,expires_at) values (handoff.request_id,caller,now()+interval '30 days')
    on conflict(request_id,user_id) do update set expires_at = excluded.expires_at;
  update public.customer_request_handoffs set used_at = now(), used_by = caller where request_id = handoff.request_id;
  return jsonb_build_object('ok',true,'request_id',handoff.request_id);
end;
$$;

revoke all on function public.customer_can_access(uuid) from public, anon, authenticated;
revoke all on function public.get_customer_request(uuid) from public, anon;
revoke all on function public.create_customer_request(float8,float8,text,text,text,text) from public, anon;
revoke all on function public.cancel_customer_request(uuid) from public, anon;
revoke all on function public.rate_customer_request(uuid,integer,text) from public, anon;
revoke all on function public.issue_customer_handoff(uuid) from public, anon;
revoke all on function public.redeem_customer_handoff(text,text) from public, anon;
grant execute on function public.get_customer_request(uuid) to authenticated;
grant execute on function public.create_customer_request(float8,float8,text,text,text,text) to authenticated;
grant execute on function public.cancel_customer_request(uuid) to authenticated;
grant execute on function public.rate_customer_request(uuid,integer,text) to authenticated;
grant execute on function public.issue_customer_handoff(uuid) to authenticated;
grant execute on function public.redeem_customer_handoff(text,text) to authenticated;

notify pgrst, 'reload schema';
commit;
-- Fazaa customer v0.2. Apply AFTER the v0.1 handoff migration.
begin;

create table if not exists public.customer_regions (
  code text primary key, name text not null, enabled boolean not null default false, sort_order integer not null default 0
);
create table if not exists public.customer_services (
  code text primary key, name text not null, description text not null default '', enabled boolean not null default false, sort_order integer not null default 0
);
create table if not exists public.customer_service_coverage (
  region_code text not null references public.customer_regions(code),
  service_code text not null references public.customer_services(code),
  enabled boolean not null default false,
  primary key(region_code,service_code)
);
insert into public.customer_regions(code,name,enabled,sort_order) values
 ('damascus','دمشق',true,1),('rif-dimashq','ريف دمشق',false,2),('aleppo','حلب',false,3),('homs','حمص',false,4),
 ('hama','حماة',false,5),('latakia','اللاذقية',false,6),('tartus','طرطوس',false,7),('idlib','إدلب',false,8),
 ('daraa','درعا',false,9),('sweida','السويداء',false,10),('quneitra','القنيطرة',false,11),
 ('deir-ezzor','دير الزور',false,12),('raqqa','الرقة',false,13),('hasakah','الحسكة',false,14)
 on conflict(code) do nothing;
insert into public.customer_services(code,name,description,enabled,sort_order) values
 ('tow','سطحة ونقل سيارة','نقل سيارتك عند العطل أو الحاجة إلى سحبها.',true,1),
 ('roadside','مساعدة على الطريق','خدمات ميدانية نجهّزها للمرحلة القادمة.',false,2),
 ('vehicle-transport','نقل مركبات','خيارات نقل إضافية سنعلن عنها عند توافرها.',false,3)
 on conflict(code) do nothing;
insert into public.customer_service_coverage(region_code,service_code,enabled) values ('damascus','tow',true)
 on conflict(region_code,service_code) do nothing;
alter table public.customer_regions enable row level security;
alter table public.customer_services enable row level security;
alter table public.customer_service_coverage enable row level security;
revoke all on public.customer_regions,public.customer_services,public.customer_service_coverage from public,anon,authenticated;

alter table public.requests add column if not exists region_code text not null default 'damascus';
alter table public.requests add column if not exists service_code text not null default 'tow';

create or replace function public.get_customer_catalog()
returns jsonb language sql stable security definer set search_path = '' as $$
 select jsonb_build_object(
  'regions',coalesce((select jsonb_agg(to_jsonb(r) order by r.sort_order) from public.customer_regions r),'[]'::jsonb),
  'services',coalesce((select jsonb_agg(to_jsonb(s) order by s.sort_order) from public.customer_services s),'[]'::jsonb),
  'coverage',coalesce((select jsonb_agg(to_jsonb(c)) from public.customer_service_coverage c where c.enabled),'[]'::jsonb)
 );
$$;

create or replace function public.create_customer_request_v2(
 p_lat float8,p_lng float8,p_problem text,p_car_type text,p_phone text,p_note text default null,
 p_region_code text default 'damascus',p_service_code text default 'tow'
) returns uuid language plpgsql security definer set search_path = '' as $$
declare request_uuid uuid;
begin
 if auth.uid() is null then raise exception 'not authenticated'; end if;
 -- Non-towing services need their own dispatch workflow before activation.
 if p_service_code <> 'tow' then raise exception 'service not available'; end if;
 if not exists(select 1 from public.customer_service_coverage c
  join public.customer_regions r on r.code=c.region_code join public.customer_services s on s.code=c.service_code
  where c.region_code=p_region_code and c.service_code=p_service_code and c.enabled and r.enabled and s.enabled
 ) then raise exception 'service not available'; end if;
 request_uuid := public.create_customer_request(p_lat,p_lng,p_problem,p_car_type,p_phone,p_note);
 update public.requests set region_code=p_region_code,service_code=p_service_code where id=request_uuid;
 return request_uuid;
end;
$$;

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
 order by r.created_at desc,r.id desc limit least(greatest(p_limit,1),50) offset greatest(p_offset,0);
$$;

-- Proof of possession of the guest session allows linking its requests to a verified account.
-- Original ownership is retained, so an existing browser can still follow its requests.
create table if not exists public.customer_account_links (
 source_user_id uuid primary key references auth.users(id) on delete cascade,
 token_hash text not null unique,expires_at timestamptz not null,
 used_at timestamptz,used_by uuid references auth.users(id) on delete set null
);
alter table public.customer_account_links enable row level security;
revoke all on public.customer_account_links from public,anon,authenticated;

create or replace function public.prepare_customer_account_link()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare secret text; expiry timestamptz := now()+interval '24 hours';
begin
 if auth.uid() is null or not coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
  return jsonb_build_object('token',null);
 end if;
 if not exists(select 1 from public.requests r where public.customer_can_access(r.id)) then
  return jsonb_build_object('token',null);
 end if;
 secret := replace(gen_random_uuid()::text,'-','');
 insert into public.customer_account_links(source_user_id,token_hash,expires_at,used_at,used_by)
 values(auth.uid(),encode(sha256(convert_to(secret,'UTF8')),'hex'),expiry,null,null)
 on conflict(source_user_id) do update set token_hash=excluded.token_hash,expires_at=excluded.expires_at,used_at=null,used_by=null;
 return jsonb_build_object('token',secret,'expires_at',expiry);
end;
$$;

create or replace function public.claim_customer_account_link(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare link public.customer_account_links%rowtype; caller uuid := auth.uid(); copied integer;
begin
 if caller is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,true) then raise exception 'verified account required'; end if;
 -- JWT alone is not used to infer that an email address was confirmed.
 if not exists(select 1 from auth.users u where u.id=caller and u.email_confirmed_at is not null) then raise exception 'verified account required'; end if;
 if coalesce(p_token,'') !~ '^[a-f0-9]{32}$' then return jsonb_build_object('ok',false); end if;
 perform pg_advisory_xact_lock(hashtextextended(caller::text,0));
 select l.* into link from public.customer_account_links l where l.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') for update;
 if not found or link.expires_at<=now() then return jsonb_build_object('ok',false); end if;
 if link.used_at is not null then return jsonb_build_object('ok',link.used_by=caller); end if;
 insert into public.customer_request_grants(request_id,user_id,expires_at)
 select r.id,caller,case when r.customer_id=link.source_user_id then 'infinity'::timestamptz else g.expires_at end
 from public.requests r left join public.customer_request_grants g on g.request_id=r.id and g.user_id=link.source_user_id and g.expires_at>now()
 where r.customer_id=link.source_user_id or g.user_id is not null
 on conflict(request_id,user_id) do update set expires_at=greatest(public.customer_request_grants.expires_at,excluded.expires_at);
 get diagnostics copied = row_count;
 update public.customer_account_links set used_at=now(),used_by=caller where source_user_id=link.source_user_id;
 return jsonb_build_object('ok',true,'linked_count',copied);
end;
$$;

revoke all on function public.get_customer_catalog() from public;
revoke all on function public.create_customer_request_v2(float8,float8,text,text,text,text,text,text) from public,anon;
revoke all on function public.get_customer_history(integer,integer) from public,anon;
revoke all on function public.prepare_customer_account_link() from public,anon;
revoke all on function public.claim_customer_account_link(text) from public,anon;
grant execute on function public.get_customer_catalog() to anon,authenticated;
grant execute on function public.create_customer_request_v2(float8,float8,text,text,text,text,text,text) to authenticated;
grant execute on function public.get_customer_history(integer,integer) to authenticated;
grant execute on function public.prepare_customer_account_link() to authenticated;
grant execute on function public.claim_customer_account_link(text) to authenticated;
notify pgrst,'reload schema';
commit;
