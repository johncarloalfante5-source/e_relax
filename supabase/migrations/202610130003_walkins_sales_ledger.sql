create table public.walk_ins (
  id uuid primary key default gen_random_uuid(),
  reference_number text not null unique default ('WI-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  client_name text not null,
  client_phone text not null default '',
  service_id text not null references public.services(id),
  service_name text not null,
  therapist_id uuid not null references public.therapists(id),
  therapist_name text not null,
  duration_minutes integer not null check(duration_minutes>0),
  total_amount numeric(12,2) not null check(total_amount>=0),
  started_at timestamptz not null default now(),
  completed_at timestamptz not null,
  checked_out_at timestamptz,
  payment_method text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((checked_out_at is null and payment_method is null) or (checked_out_at is not null and payment_method is not null))
);
create or replace function public.set_walk_in_completion_time()
returns trigger language plpgsql set search_path=public
as $$
begin
  new.completed_at := new.started_at+make_interval(mins=>new.duration_minutes+5);
  return new;
end;
$$;
create trigger walk_ins_set_completion_time before insert or update on public.walk_ins
for each row execute procedure public.set_walk_in_completion_time();
create index walk_ins_started_idx on public.walk_ins(started_at);
create index walk_ins_completed_idx on public.walk_ins(completed_at);
create index walk_ins_checkout_idx on public.walk_ins(checked_out_at);

alter table public.walk_ins enable row level security;
-- Walk-in creation and checkout must use RPCs so the timer and sales ledger
-- are updated together, regardless of project-wide default table grants.
revoke all on public.walk_ins from public, anon, authenticated;
grant select on public.walk_ins to authenticated;
create policy "staff manage walkins" on public.walk_ins for all to authenticated using (public.current_app_role() in ('admin','cashier')) with check (public.current_app_role() in ('admin','cashier'));
-- Ledger writes are performed only by the security-definer checkout/payment
-- RPCs, preserving idempotency and preventing fabricated report revenue.

create or replace function public.start_walk_in(p_client_name text,p_client_phone text,p_service_id text,p_therapist_id uuid)
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare s public.services; t public.therapists; v_id uuid;
begin
  if public.current_app_role() not in ('admin','cashier') then raise exception 'Cashier access required'; end if;
  select * into s from public.services where id=p_service_id and active;
  select * into t from public.therapists where id=p_therapist_id and active;
  if s.id is null or t.id is null then raise exception 'Choose an active service and therapist'; end if;
  if not exists(select 1 from public.services specialty where specialty.id=t.specialty_service_id and specialty.name=s.name) then raise exception 'Therapist does not provide this massage service'; end if;
  if not exists(select 1 from public.therapist_duty where therapist_id=t.id and work_date=(now() at time zone 'Asia/Manila')::date) then raise exception 'Therapist is not on duty today'; end if;
  -- Use the same per-therapist lock as online booking creation to prevent
  -- simultaneous requests from reserving overlapping time.
  perform pg_advisory_xact_lock(hashtextextended(t.id::text,0));
  if exists(select 1 from public.bookings b where b.therapist_id=t.id and b.status<>'cancelled'
    and b.slot && tstzrange(now(),now()+make_interval(mins=>s.duration_minutes+5),'[)')) then raise exception 'Therapist has an online booking during this service'; end if;
  if exists(select 1 from public.walk_ins w where w.therapist_id=t.id and w.completed_at>now()) then raise exception 'Therapist is already serving a walk-in'; end if;
  insert into public.walk_ins(client_name,client_phone,service_id,service_name,therapist_id,therapist_name,duration_minutes,total_amount,created_by)
   values(trim(p_client_name),coalesce(trim(p_client_phone),''),s.id,s.name,t.id,t.name,s.duration_minutes,s.price,auth.uid()) returning id into v_id;
  return v_id;
end $$;

create or replace function public.available_therapists(p_date date,p_start_at timestamptz,p_duration integer,p_service_id text)
returns table(id uuid,name text,specialty_service_id text,profile_image_path text)
language sql stable security definer set search_path=public,auth
as $$
  select t.id,t.name,t.specialty_service_id,t.profile_image_path
  from public.therapists t join public.therapist_duty d on d.therapist_id=t.id and d.work_date=p_date
  where t.active
    and exists(select 1 from public.services selected join public.services specialty on specialty.id=t.specialty_service_id where selected.id=p_service_id and selected.active and specialty.name=selected.name)
    and not exists(select 1 from public.bookings b where b.therapist_id=t.id and b.status<>'cancelled'
      and b.slot && tstzrange(p_start_at,p_start_at+make_interval(mins=>p_duration),'[)'))
    and not exists(select 1 from public.walk_ins w where w.therapist_id=t.id and w.completed_at>now()
      and tstzrange(w.started_at,w.completed_at,'[)') && tstzrange(p_start_at,p_start_at+make_interval(mins=>p_duration),'[)'));
$$;

create or replace function public.checkout_walk_in(p_walk_in_id uuid,p_method text)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare w public.walk_ins; v_key text;
begin
  if public.current_app_role() not in ('admin','cashier') then raise exception 'Cashier access required'; end if;
  if p_method not in ('Cash','Card','GCash') then raise exception 'Choose a valid payment method'; end if;
  select * into w from public.walk_ins where id=p_walk_in_id for update;
  if not found then raise exception 'Walk-in not found'; end if;
  if w.checked_out_at is not null then return; end if;
  v_key := 'walkin:'||w.id::text;
  update public.walk_ins set checked_out_at=now(),payment_method=p_method,updated_at=now() where id=w.id;
  insert into public.payment_transactions(source_type,source_id,amount,method,actor_id,idempotency_key)
   values('walk_in',w.id,w.total_amount,p_method,auth.uid(),v_key) on conflict(idempotency_key) do nothing;
end $$;

create or replace function public.collect_online_balance(p_booking_id uuid,p_method text)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare b public.bookings; v_paid numeric(12,2); v_amount numeric(12,2); v_key text;
begin
  if public.current_app_role() not in ('admin','cashier') then raise exception 'Cashier access required'; end if;
  if p_method not in ('Cash','Card','GCash') then raise exception 'Choose a valid payment method'; end if;
  select * into b from public.bookings where id=p_booking_id for update;
  if not found or b.status <> 'completed' then raise exception 'Service must be completed before collecting the balance'; end if;
  select coalesce(sum(amount),0) into v_paid from public.payment_transactions where source_id=b.id and source_type in ('booking_deposit','booking_balance');
  v_amount := b.total_amount-v_paid;
  if v_amount <= 0 then return; end if;
  v_key := 'balance:'||b.id::text;
  insert into public.payment_transactions(source_type,source_id,amount,method,actor_id,idempotency_key)
   values('booking_balance',b.id,v_amount,p_method,auth.uid(),v_key) on conflict(idempotency_key) do nothing;
  insert into public.booking_activity(booking_id,actor_id,event,note) values(b.id,auth.uid(),'balance_collected',p_method);
  insert into public.notifications(user_id,booking_id,event_key,title,message)
   values(b.client_id,b.id,'balance_collected:'||b.id::text,'Balance paid','Your remaining appointment balance has been collected.') on conflict(user_id,event_key) do nothing;
end $$;

grant execute on function public.start_walk_in(text,text,text,uuid), public.checkout_walk_in(uuid,text), public.collect_online_balance(uuid,text) to authenticated;
grant execute on function public.available_therapists(date,timestamptz,integer,text) to authenticated;
revoke execute on function public.start_walk_in(text,text,text,uuid), public.checkout_walk_in(uuid,text), public.collect_online_balance(uuid,text) from public, anon;
revoke execute on function public.available_therapists(date,timestamptz,integer,text) from public, anon;
