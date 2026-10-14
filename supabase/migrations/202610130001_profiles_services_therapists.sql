-- E-Relax shared identity and clinic catalog foundation.
create extension if not exists pgcrypto;

create type public.app_role as enum ('client', 'admin', 'cashier', 'therapist');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role not null default 'client',
  display_name text not null default '',
  email text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns public.app_role language sql stable security definer
set search_path = public, auth
as $$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.has_staff_role()
returns boolean language sql stable security definer
set search_path = public, auth
as $$ select coalesce(public.current_app_role() in ('admin', 'cashier', 'therapist'), false) $$;

create or replace function public.create_client_profile()
returns trigger language plpgsql security definer set search_path = public, auth
as $$
begin
  insert into public.profiles (id, role, display_name, email)
  values (new.id, 'client', coalesce(new.raw_user_meta_data->>'display_name', ''), new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created_profile after insert on auth.users
for each row execute procedure public.create_client_profile();

create table public.services (
  id text primary key,
  name text not null,
  description text not null default '',
  price numeric(12,2) not null check (price >= 0),
  duration_minutes integer not null check (duration_minutes > 0),
  rating numeric(3,2),
  image_url text,
  semantic_label text,
  category text not null default '',
  display_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.therapists (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  email text,
  phone text,
  specialty_service_id text not null references public.services(id),
  auth_profile_id uuid unique references public.profiles(id) on delete set null,
  profile_image_path text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.therapist_duty (
  id uuid primary key default gen_random_uuid(),
  therapist_id uuid not null references public.therapists(id) on delete cascade,
  work_date date not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (therapist_id, work_date)
);

-- Realtime cannot subscribe to views. Publish a harmless change token so
-- client/cashier devices can refresh the sanitized directory view safely.
create table public.therapist_directory_events (
  therapist_id uuid primary key,
  changed_at timestamptz not null default now()
);
alter table public.therapist_directory_events enable row level security;
revoke all on public.therapist_directory_events from public, anon, authenticated;
grant select on public.therapist_directory_events to authenticated;
create policy "authenticated refresh public therapist directory" on public.therapist_directory_events
  for select to authenticated using (true);

create or replace function public.publish_therapist_directory_change()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.therapist_directory_events(therapist_id)
  values(coalesce(new.id,old.id))
  on conflict(therapist_id) do update set changed_at=now();
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
create trigger therapist_directory_changed after insert or update or delete on public.therapists
for each row execute procedure public.publish_therapist_directory_change();

create index therapist_duty_work_date_idx on public.therapist_duty(work_date);
create index therapists_active_idx on public.therapists(active);

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.therapists enable row level security;
alter table public.therapist_duty enable row level security;

-- Remove project-wide default table privileges before granting the narrow
-- profile operations. In particular, users must never update their own role.
revoke all on public.profiles from public, anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, phone, updated_at) on public.profiles to authenticated;
grant select on public.services to anon, authenticated;
grant select on public.therapists, public.therapist_duty to anon, authenticated;
grant insert, update, delete on public.services, public.therapists, public.therapist_duty to authenticated;
revoke select on public.therapists from anon;

create policy "profile owner or operations staff reads profile" on public.profiles for select to authenticated using (id = auth.uid() or public.current_app_role() in ('admin','cashier'));
create policy "profile owner edits contact fields" on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());
create policy "services visible" on public.services for select to anon, authenticated using (active or public.current_app_role() in ('admin','cashier'));
create policy "admin manages services" on public.services for all to authenticated using (public.current_app_role() = 'admin') with check (public.current_app_role() = 'admin');
create policy "operations staff or therapist owner reads therapist rows" on public.therapists for select to authenticated using (
  public.current_app_role()='admin' or auth_profile_id=auth.uid()
);
create policy "admin manages therapists" on public.therapists for all to authenticated using (public.current_app_role() = 'admin') with check (public.current_app_role() = 'admin');
create policy "duty visible" on public.therapist_duty for select to anon, authenticated using (true);
create policy "admin manages duty" on public.therapist_duty for all to authenticated using (public.current_app_role() = 'admin') with check (public.current_app_role() = 'admin');

create view public.clinic_therapists with (security_barrier=true) as
  select id,name,specialty_service_id,profile_image_path,active,created_at,updated_at
  from public.therapists where active;
grant select on public.clinic_therapists to anon,authenticated;

create or replace function public.save_therapist_duty(p_work_date date,p_therapist_ids uuid[])
returns void language plpgsql security definer set search_path=public,auth
as $$
begin
  if public.current_app_role()<>'admin' then raise exception 'Admin access required'; end if;
  if exists(select 1 from unnest(p_therapist_ids) selected(id) left join public.therapists t on t.id=selected.id where t.id is null or not t.active) then
    raise exception 'Duty roster includes an unavailable therapist';
  end if;
  delete from public.therapist_duty where work_date=p_work_date;
  insert into public.therapist_duty(therapist_id,work_date,created_by)
    select distinct selected.therapist_id,p_work_date,auth.uid() from unnest(p_therapist_ids) as selected(therapist_id);
end $$;
grant execute on function public.save_therapist_duty(date,uuid[]) to authenticated;
revoke execute on function public.save_therapist_duty(date,uuid[]) from public,anon;

insert into public.services (id,name,description,price,duration_minutes,rating,image_url,semantic_label,category,display_order)
values
('svc_001','Whole Body Massage','A full-body relaxation massage covering all major muscle groups for complete stress relief and rejuvenation.',350,60,4.9,'https://img.rocket.new/generatedImages/rocket_gen_img_13f957847-1772520779967.png','Therapist performing full body massage on client lying on white table with soft lighting','Full Body',1),
('svc_002','Lying/Back Massage','Focused back and lying massage targeting tension in the back, shoulders, and neck for quick relief.',180,30,4.8,'https://img.rocket.new/generatedImages/rocket_gen_img_14dceb6ca-1767700592429.png','Back massage being performed on client lying face down in spa setting','Back',2),
('svc_003','Foot Massage','A comprehensive foot massage using reflexology techniques to relieve fatigue and improve circulation throughout the body.',350,60,4.7,'https://img.rocket.new/generatedImages/rocket_gen_img_48b189a0c-1789227680293.png','Therapist performing relaxing foot massage on client feet in spa environment','Foot',3),
('svc_004','Foot Massage','A focused foot massage session targeting pressure points to relieve stress and restore energy balance.',180,30,4.6,'https://img.rocket.new/generatedImages/rocket_gen_img_4f02899be-1790507336525.png','Foot reflexology massage with therapist applying pressure to sole of client foot','Foot',4)
on conflict (id) do update set name=excluded.name, description=excluded.description, price=excluded.price,
duration_minutes=excluded.duration_minutes, rating=excluded.rating, image_url=excluded.image_url,
semantic_label=excluded.semantic_label, category=excluded.category, display_order=excluded.display_order;

-- Promote a trusted first admin only through the SQL editor, after creating the auth account:
-- update public.profiles set role='admin' where email='your-admin@example.com';
