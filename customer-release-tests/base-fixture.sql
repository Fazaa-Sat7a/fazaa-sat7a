-- DISPOSABLE DATABASE ONLY. Never apply to the production project.
do $$ begin if current_database()<>'fazaa_commercial_test' then raise exception 'Disposable test database required'; end if; end $$;
create role anon nologin;create role authenticated nologin;create role service_role nologin bypassrls;
create schema auth;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function auth.uid() returns uuid language sql stable as $$select nullif(auth.jwt()->>'sub','')::uuid$$;
grant usage on schema auth,public to anon,authenticated,service_role;
grant execute on function auth.jwt(),auth.uid() to anon,authenticated,service_role;
create table public.admins(id uuid primary key references auth.users(id));
create function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.admins where id=auth.uid())$$;
create table public.drivers(id uuid primary key references auth.users(id),name text not null,phone text,plate text,truck_type text default 'standard',area text,status text not null default 'active',is_available boolean default true,lat float8,lng float8,location_updated_at timestamptz,created_at timestamptz default now());
create table public.requests(id uuid primary key default gen_random_uuid(),customer_id uuid not null references auth.users(id),driver_id uuid references public.drivers(id),status text not null default 'new',problem text,car_type text,customer_phone text,note text,lat float8,lng float8,short_code text default (100000+floor(random()*899999))::integer::text,created_at timestamptz not null default now(),accepted_at timestamptz,arrived_at timestamptz,done_at timestamptz,cancelled_at timestamptz);
create table public.ratings(id uuid primary key default gen_random_uuid(),request_id uuid unique not null references public.requests(id),driver_id uuid not null references public.drivers(id),stars integer check(stars between 1 and 5),comment text,created_at timestamptz default now());
alter table public.ratings enable row level security;
create policy fixture_rating_select on public.ratings for select to authenticated using(true);
grant select on public.ratings to authenticated;
create function public.create_request(p_lat float8,p_lng float8,p_problem text,p_car_type text,p_phone text,p_note text default null) returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 if auth.uid() is null then raise exception 'not authenticated';end if;
 if exists(select 1 from public.requests where customer_id=auth.uid() and (status in ('accepted','arrived','in_progress') or (status='new' and created_at>now()-interval '15 minutes'))) then raise exception 'active request exists';end if;
 insert into public.requests(customer_id,lat,lng,problem,car_type,customer_phone,note) values(auth.uid(),p_lat,p_lng,p_problem,p_car_type,p_phone,p_note) returning id into result;return result;end$$;
create function public.driver_open_requests(p_radius_km float8 default 15) returns table(id uuid,problem text,car_type text,lat float8,lng float8,created_at timestamptz,note text,distance_km float8) language sql stable security definer set search_path='' as $$select r.id,r.problem,r.car_type,r.lat,r.lng,r.created_at,r.note,1::float8 from public.requests r where r.status='new' and r.created_at>now()-interval '15 minutes' and exists(select 1 from public.drivers where id=auth.uid() and status='active' and is_available)$$;
create function public.driver_accept_request(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$declare changed integer;begin
 perform 1 from public.drivers where id=auth.uid() and status='active' and is_available for update;
 if not found then return false;end if;
 update public.requests set driver_id=auth.uid(),status='accepted',accepted_at=now() where id=p_id and status='new' and created_at>now()-interval '15 minutes';get diagnostics changed=row_count;return changed=1;end$$;
grant execute on function public.driver_open_requests(float8),public.driver_accept_request(uuid) to authenticated;
create function public.test_assert(ok boolean,note text) returns void language plpgsql as $$begin if not coalesce(ok,false) then raise exception 'ASSERTION: %',note;end if;end$$;
create function public.expect_error(statement text,expected text) returns void language plpgsql as $$begin execute statement;raise exception 'EXPECTED_ERROR_NOT_RAISED';exception when others then if position(expected in sqlerrm)=0 then raise;end if;end$$;
insert into auth.users(id,email_confirmed_at) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now()),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',now()),('cccccccc-cccc-4ccc-8ccc-cccccccccccc',now()),('dddddddd-dddd-4ddd-8ddd-dddddddddddd',now()),('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',now());
insert into public.admins values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into public.drivers(id,name,plate) values('dddddddd-dddd-4ddd-8ddd-dddddddddddd','Fixture driver','TEST-1'),('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','Wrong size driver','TEST-2');
