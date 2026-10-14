create extension if not exists btree_gist;

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  reference_number text not null unique default ('ER-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  client_id uuid not null references public.profiles(id),
  client_name text not null,
  client_phone text not null default '',
  client_email text not null default '',
  service_id text not null references public.services(id),
  service_name text not null,
  service_description text not null default '',
  therapist_id uuid not null references public.therapists(id),
  therapist_name text not null,
  appointment_date date not null,
  start_time text not null,
  start_at timestamptz not null,
  duration_minutes integer not null check (duration_minutes > 0),
  total_amount numeric(12,2) not null check (total_amount >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  status text not null default 'pendingPayment' check (status in ('pendingPayment','confirmed','checkedIn','inProgress','completed','cancelled')),
  checked_in_at timestamptz,
  service_started_at timestamptz,
  service_completed_at timestamptz,
  cancellation_reason text,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  slot tstzrange not null
);
create or replace function public.set_booking_slot()
returns trigger language plpgsql set search_path=public
as $$
begin
  new.slot := tstzrange(new.start_at,new.start_at+make_interval(mins=>new.duration_minutes),'[)');
  return new;
end;
$$;
create trigger bookings_set_slot before insert or update on public.bookings
for each row execute procedure public.set_booking_slot();
create index bookings_client_date_idx on public.bookings(client_id, appointment_date desc);
create index bookings_status_date_idx on public.bookings(status, appointment_date);
alter table public.bookings add constraint bookings_therapist_slot_exclusion
  exclude using gist (therapist_id with =, slot with &&) where (status <> 'cancelled');

create table public.payment_submissions (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  submission_number integer not null,
  transaction_reference text not null,
  amount numeric(12,2) not null check (amount > 0),
  proof_path text not null,
  status text not null default 'Pending Verification' check (status in ('Pending Verification','Verified','Rejected')),
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  rejection_reason text,
  unique (booking_id, submission_number)
);
create unique index one_verified_submission_per_booking on public.payment_submissions(booking_id) where status='Verified';

create table public.booking_activity (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  actor_id uuid references public.profiles(id),
  event text not null,
  note text,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,
  event_key text not null,
  title text not null,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique (user_id, event_key)
);

create table public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check (source_type in ('booking_deposit','booking_balance','walk_in')),
  source_id uuid not null,
  amount numeric(12,2) not null check (amount > 0),
  method text not null,
  actor_id uuid references public.profiles(id),
  idempotency_key text not null unique,
  captured_at timestamptz not null default now()
);

alter table public.bookings enable row level security;
alter table public.payment_submissions enable row level security;
alter table public.booking_activity enable row level security;
alter table public.notifications enable row level security;
alter table public.payment_transactions enable row level security;
-- Supabase projects may have permissive default grants on public tables.
-- All writes to these records must pass through validated RPCs.
revoke all on public.bookings, public.payment_submissions, public.booking_activity,
  public.notifications, public.payment_transactions from public, anon, authenticated;
grant select on public.bookings, public.payment_submissions, public.booking_activity, public.notifications to authenticated;
grant select on public.payment_transactions to authenticated;
grant update(read_at) on public.notifications to authenticated;

create policy "booking owner or assigned staff read" on public.bookings for select to authenticated using (
  client_id=auth.uid() or public.current_app_role() in ('admin','cashier') or
  exists(select 1 from public.therapists t where t.id=therapist_id and t.auth_profile_id=auth.uid())
);
create policy "booking client own insert pending" on public.bookings for insert to authenticated with check (client_id=auth.uid() and status='pendingPayment');
-- Status changes are RPC-only so clients and staff cannot bypass payment,
-- booking lifecycle, and audit checks with direct table updates.
create policy "submission client or staff read" on public.payment_submissions for select to authenticated using (
  exists(select 1 from public.bookings b where b.id=booking_id and (b.client_id=auth.uid() or public.current_app_role() in ('admin','cashier') or exists(select 1 from public.therapists t where t.id=b.therapist_id and t.auth_profile_id=auth.uid())))
);
create policy "activity client or staff read" on public.booking_activity for select to authenticated using (
  exists(select 1 from public.bookings b where b.id=booking_id and (b.client_id=auth.uid() or public.current_app_role() in ('admin','cashier') or exists(select 1 from public.therapists t where t.id=b.therapist_id and t.auth_profile_id=auth.uid())))
);
create policy "notification owner read" on public.notifications for select to authenticated using (user_id=auth.uid());
create policy "notification owner marks read" on public.notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy "ledger owner or staff read" on public.payment_transactions for select to authenticated using (
  public.current_app_role() in ('admin','cashier') or (source_type in ('booking_deposit','booking_balance') and exists(select 1 from public.bookings b where b.id=source_id and b.client_id=auth.uid()))
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('payment-proofs','payment-proofs',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('therapist-profiles','therapist-profiles',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true;

create policy "client uploads own proof" on storage.objects for insert to authenticated with check (
  bucket_id='payment-proofs' and (storage.foldername(name))[1]=auth.uid()::text
);
create policy "client or staff reads proof" on storage.objects for select to authenticated using (
  bucket_id='payment-proofs' and (public.current_app_role() in ('admin','cashier') or (storage.foldername(name))[1]=auth.uid()::text)
);
create policy "admin manages therapist photos" on storage.objects for all to authenticated using (
  bucket_id='therapist-profiles' and public.current_app_role()='admin'
) with check (bucket_id='therapist-profiles' and public.current_app_role()='admin');

create or replace function public.create_online_booking(p_service_id text, p_therapist_id uuid,
  p_appointment_date date, p_start_time text, p_start_at timestamptz,
  p_client_name text, p_client_phone text, p_client_email text,
  p_transaction_reference text, p_proof_path text)
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare v_booking public.bookings; v_service public.services; v_therapist public.therapists;
  v_submission uuid; v_amount numeric(12,2); v_hour integer; v_minute integer; v_clock integer;
  v_local_start timestamp;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if (storage.foldername(p_proof_path))[1] <> auth.uid()::text then raise exception 'Proof must be uploaded to your private account folder'; end if;
  if not exists(select 1 from storage.objects where bucket_id='payment-proofs' and name=p_proof_path) then raise exception 'Uploaded payment proof was not found'; end if;
  select * into v_service from public.services where id=p_service_id and active;
  if not found then raise exception 'Service is unavailable'; end if;
  select t.* into v_therapist from public.therapists t join public.therapist_duty d on d.therapist_id=t.id
    where t.id=p_therapist_id and t.active and d.work_date=p_appointment_date;
  if not found then raise exception 'Therapist is not on duty for this date'; end if;
  if not exists(select 1 from public.services specialty where specialty.id=v_therapist.specialty_service_id and specialty.name=v_service.name) then
    raise exception 'Therapist does not provide this massage service';
  end if;
  -- Serialize booking and walk-in creation for this therapist so both paths
  -- observe each other's committed reservations.
  perform pg_advisory_xact_lock(hashtextextended(p_therapist_id::text,0));
  if not exists(select 1 from public.therapist_duty where therapist_id=p_therapist_id and work_date=p_appointment_date) then raise exception 'Therapist is not on duty'; end if;
  if p_start_time !~* '^(0?[1-9]|1[0-2]):[0-5][0-9] (AM|PM)$' then raise exception 'Invalid appointment time'; end if;
  v_hour := split_part(p_start_time,':',1)::integer;
  v_minute := substring(p_start_time from position(':' in p_start_time)+1 for 2)::integer;
  v_clock := ((v_hour % 12) + case when upper(right(p_start_time,2))='PM' then 12 else 0 end)*60 + v_minute;
  v_local_start := p_start_at at time zone 'Asia/Manila';
  if v_local_start::date <> p_appointment_date
    or extract(hour from v_local_start)::integer*60 + extract(minute from v_local_start)::integer <> v_clock
    or extract(second from v_local_start) <> 0
    or v_clock < 660 or v_clock > 1200 or v_clock % 5 <> 0 then
    raise exception 'Choose a valid five-minute slot between 11:00 AM and 8:00 PM'; end if;
  if p_start_at <= now() then raise exception 'Choose a future appointment time'; end if;
  if exists(select 1 from public.walk_ins w where w.therapist_id=p_therapist_id
    and w.completed_at > now()
    and tstzrange(w.started_at,w.completed_at,'[)') && tstzrange(p_start_at,p_start_at+make_interval(mins=>v_service.duration_minutes),'[)')) then
    raise exception 'Therapist is already serving a walk-in during this appointment';
  end if;
  v_amount := round(v_service.price * 0.30);
  insert into public.bookings(client_id,client_name,client_phone,client_email,service_id,service_name,service_description,
    therapist_id,therapist_name,appointment_date,start_time,start_at,duration_minutes,total_amount)
  values(auth.uid(),p_client_name,p_client_phone,p_client_email,v_service.id,v_service.name,v_service.description,
    v_therapist.id,v_therapist.name,p_appointment_date,p_start_time,p_start_at,v_service.duration_minutes,v_service.price)
  returning * into v_booking;
  insert into public.payment_submissions(booking_id,submission_number,transaction_reference,amount,proof_path)
  values(v_booking.id,1,p_transaction_reference,v_amount,p_proof_path) returning id into v_submission;
  insert into public.booking_activity(booking_id,actor_id,event) values(v_booking.id,auth.uid(),'booking_created'),(v_booking.id,auth.uid(),'proof_submitted');
  return v_booking.id;
end $$;

create or replace function public.verify_payment(p_submission_id uuid)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare s public.payment_submissions; b public.bookings; v_event text;
begin
  if public.current_app_role() not in ('admin','cashier') then raise exception 'Staff access required'; end if;
  select * into s from public.payment_submissions where id=p_submission_id for update;
  if not found then raise exception 'Payment submission not found'; end if;
  select * into b from public.bookings where id=s.booking_id for update;
  if s.status='Verified' then return; end if;
  if s.status <> 'Pending Verification' or s.proof_path='' or trim(s.transaction_reference)='' then raise exception 'Submission is not verifiable'; end if;
  if b.status <> 'pendingPayment' then raise exception 'Booking is no longer awaiting payment verification'; end if;
  if s.amount <> round(b.total_amount*0.30) then raise exception 'Down payment amount is incorrect'; end if;
  update public.payment_submissions set status='Verified', reviewed_at=now(), reviewed_by=auth.uid() where id=s.id;
  update public.bookings set status='confirmed', updated_at=now() where id=b.id and status='pendingPayment';
  insert into public.payment_transactions(source_type,source_id,amount,method,actor_id,idempotency_key)
    values('booking_deposit',b.id,s.amount,'InstaPay',auth.uid(),'deposit:'||s.id::text)
    on conflict(idempotency_key) do nothing;
  insert into public.booking_activity(booking_id,actor_id,event) values(b.id,auth.uid(),'payment_verified'),(b.id,auth.uid(),'booking_confirmed');
  v_event := 'payment_verified:'||s.id::text;
  insert into public.notifications(user_id,booking_id,event_key,title,message)
    values(b.client_id,b.id,v_event,'Payment verified','Your 30% down payment is verified. '||b.service_name||' is confirmed for '||b.appointment_date::text||' at '||b.start_time||'. Booking reference: '||b.reference_number||'.') on conflict(user_id,event_key) do nothing;
end $$;

create or replace function public.reject_payment(p_submission_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare s public.payment_submissions; b public.bookings;
begin
  if public.current_app_role() not in ('admin','cashier') then raise exception 'Staff access required'; end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'A rejection reason is required'; end if;
  select * into s from public.payment_submissions where id=p_submission_id for update;
  if not found then raise exception 'Payment submission not found'; end if;
  if s.status='Rejected' then return; end if;
  if s.status <> 'Pending Verification' then raise exception 'Submission is already reviewed'; end if;
  select * into b from public.bookings where id=s.booking_id for update;
  update public.payment_submissions set status='Rejected',rejection_reason=trim(p_reason),reviewed_at=now(),reviewed_by=auth.uid() where id=s.id;
  insert into public.booking_activity(booking_id,actor_id,event,note) values(b.id,auth.uid(),'payment_rejected',trim(p_reason));
  insert into public.notifications(user_id,booking_id,event_key,title,message)
    values(b.client_id,b.id,'payment_rejected:'||s.id::text,'Payment proof rejected',trim(p_reason)) on conflict(user_id,event_key) do nothing;
end $$;

create or replace function public.resubmit_payment_proof(p_booking_id uuid,p_reference text,p_path text)
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare b public.bookings; v_id uuid; v_next integer; v_amount numeric(12,2);
begin
  select * into b from public.bookings where id=p_booking_id and client_id=auth.uid() for update;
  if not found then raise exception 'Booking not found'; end if;
  if (select status from public.payment_submissions where booking_id=b.id order by submission_number desc limit 1) <> 'Rejected' then raise exception 'The latest proof must be rejected before resubmission'; end if;
  if b.status <> 'pendingPayment' then raise exception 'Only an active pending booking can receive replacement proof'; end if;
  if trim(coalesce(p_reference,''))='' or trim(coalesce(p_path,''))='' then raise exception 'Reference and proof are required'; end if;
  if (storage.foldername(p_path))[1] <> auth.uid()::text then raise exception 'Proof must be in your private account folder'; end if;
  if not exists(select 1 from storage.objects where bucket_id='payment-proofs' and name=p_path) then raise exception 'Uploaded payment proof was not found'; end if;
  select coalesce(max(submission_number),0)+1 into v_next from public.payment_submissions where booking_id=b.id;
  v_amount := round(b.total_amount*0.30);
  insert into public.payment_submissions(booking_id,submission_number,transaction_reference,amount,proof_path)
    values(b.id,v_next,trim(p_reference),v_amount,p_path) returning id into v_id;
  update public.bookings set status='pendingPayment',updated_at=now() where id=b.id;
  insert into public.booking_activity(booking_id,actor_id,event) values(b.id,auth.uid(),'proof_resubmitted');
  return v_id;
end $$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language sql security invoker set search_path=public
as $$ update public.notifications set read_at=coalesce(read_at,now()) where id=p_notification_id and user_id=auth.uid() $$;

create or replace function public.transition_booking(p_booking_id uuid,p_status text,p_reason text default null)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare b public.bookings; v_event text;
begin
  select * into b from public.bookings where id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if public.current_app_role() not in ('admin','cashier','therapist') then raise exception 'Staff access required'; end if;
  if public.current_app_role()='therapist' and not exists(select 1 from public.therapists t where t.auth_profile_id=auth.uid() and t.id=b.therapist_id) then raise exception 'This appointment is not assigned to you'; end if;
  if p_status='confirmed' then
    if b.status not in ('pendingPayment','confirmed') then raise exception 'Only a payment-pending booking can be confirmed'; end if;
    if not exists(select 1 from public.payment_submissions s where s.booking_id=b.id and s.status='Verified') then raise exception 'Payment must be verified before confirmation'; end if;
  elsif p_status='checkedIn' then
    if b.status <> 'confirmed' then raise exception 'Only a confirmed booking can be checked in'; end if;
  elsif p_status='inProgress' then
    if b.status <> 'checkedIn' then raise exception 'Check in before starting service'; end if;
  elsif p_status='completed' then
    if b.status <> 'inProgress' then raise exception 'Only an in-progress service can be completed'; end if;
    if b.service_started_at + make_interval(mins=>b.duration_minutes+5) > now() then raise exception 'The service timer has not completed'; end if;
  elsif p_status='cancelled' then
    if b.status in ('completed','cancelled') or trim(coalesce(p_reason,''))='' then raise exception 'Cancellation requires an active booking and a reason'; end if;
  else raise exception 'Unsupported booking status'; end if;
  if b.status=p_status then return; end if;
  v_event := case p_status when 'confirmed' then 'booking_confirmed' when 'checkedIn' then 'client_checked_in' when 'inProgress' then 'service_started' when 'completed' then 'service_completed' else 'booking_cancelled' end;
  update public.bookings set status=p_status,
    checked_in_at=case when p_status='checkedIn' then now() else checked_in_at end,
    service_started_at=case when p_status='inProgress' then now() else service_started_at end,
    service_completed_at=case when p_status='completed' then now() else service_completed_at end,
    cancellation_reason=case when p_status='cancelled' then trim(p_reason) else cancellation_reason end,
    cancelled_at=case when p_status='cancelled' then now() else cancelled_at end,
    cancelled_by=case when p_status='cancelled' then auth.uid() else cancelled_by end,
    updated_at=now() where id=b.id;
  insert into public.booking_activity(booking_id,actor_id,event,note) values(b.id,auth.uid(),v_event,case when p_status='cancelled' then trim(p_reason) else null end);
  if p_status in ('confirmed','cancelled') then
    insert into public.notifications(user_id,booking_id,event_key,title,message) values(b.client_id,b.id,p_status||':'||b.id::text,
      case when p_status='confirmed' then 'Appointment confirmed' else 'Appointment cancelled' end,
      case when p_status='confirmed' then b.service_name||' is confirmed for '||b.appointment_date::text||' at '||b.start_time||'.' else 'Appointment cancelled: '||trim(p_reason) end)
      on conflict(user_id,event_key) do nothing;
  end if;
end $$;

grant execute on function public.create_online_booking(text,uuid,date,text,timestamptz,text,text,text,text,text) to authenticated;
grant execute on function public.verify_payment(uuid), public.reject_payment(uuid,text), public.resubmit_payment_proof(uuid,text,text), public.mark_notification_read(uuid), public.transition_booking(uuid,text,text) to authenticated;
revoke execute on function public.create_online_booking(text,uuid,date,text,timestamptz,text,text,text,text,text) from public, anon;
revoke execute on function public.verify_payment(uuid), public.reject_payment(uuid,text), public.resubmit_payment_proof(uuid,text,text), public.mark_notification_read(uuid), public.transition_booking(uuid,text,text) from public, anon;
