-- A therapist's listed specialty is informational. Any active, on-duty,
-- unoccupied therapist may provide any active massage service.

create or replace function public.create_online_booking(
  p_service_id text,
  p_therapist_id uuid,
  p_appointment_date date,
  p_start_time text,
  p_start_at timestamptz,
  p_client_name text,
  p_client_phone text,
  p_client_email text,
  p_transaction_reference text,
  p_proof_path text
)
returns uuid
language plpgsql security definer set search_path=public,auth
as $$
declare
  v_booking public.bookings;
  v_service public.services;
  v_therapist public.therapists;
  v_submission uuid;
  v_amount numeric(12,2);
  v_hour integer;
  v_minute integer;
  v_clock integer;
  v_local_start timestamp;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if (storage.foldername(p_proof_path))[1] <> auth.uid()::text then
    raise exception 'Proof must be uploaded to your private account folder';
  end if;
  if not exists (
    select 1 from storage.objects
    where bucket_id='payment-proofs' and name=p_proof_path
  ) then raise exception 'Uploaded payment proof was not found'; end if;

  select * into v_service from public.services where id=p_service_id and active;
  if not found then raise exception 'Service is unavailable'; end if;
  select t.* into v_therapist
  from public.therapists t
  join public.therapist_duty d on d.therapist_id=t.id
  where t.id=p_therapist_id and t.active and d.work_date=p_appointment_date;
  if not found then raise exception 'Therapist is not on duty for this date'; end if;

  -- Serialize booking and walk-in creation for this therapist so both paths
  -- observe each other's committed reservations.
  perform pg_advisory_xact_lock(hashtextextended(p_therapist_id::text,0));
  if not exists (
    select 1 from public.therapist_duty
    where therapist_id=p_therapist_id and work_date=p_appointment_date
  ) then raise exception 'Therapist is not on duty'; end if;
  if p_start_time !~* '^(0?[1-9]|1[0-2]):[0-5][0-9] (AM|PM)$' then
    raise exception 'Invalid appointment time';
  end if;
  v_hour := split_part(p_start_time,':',1)::integer;
  v_minute := substring(p_start_time from position(':' in p_start_time)+1 for 2)::integer;
  v_clock := ((v_hour % 12) + case when upper(right(p_start_time,2))='PM' then 12 else 0 end)*60 + v_minute;
  v_local_start := p_start_at at time zone 'Asia/Manila';
  if v_local_start::date <> p_appointment_date
    or extract(hour from v_local_start)::integer*60 + extract(minute from v_local_start)::integer <> v_clock
    or extract(second from v_local_start) <> 0
    or v_clock < 660 or v_clock > 1200 or v_clock % 5 <> 0 then
    raise exception 'Choose a valid five-minute slot between 11:00 AM and 8:00 PM';
  end if;
  if p_start_at <= now() then raise exception 'Choose a future appointment time'; end if;
  if exists (
    select 1 from public.walk_ins w
    where w.therapist_id=p_therapist_id and w.completed_at > now()
      and tstzrange(w.started_at,w.completed_at,'[)')
          && tstzrange(p_start_at,p_start_at+make_interval(mins=>v_service.duration_minutes),'[)')
  ) then raise exception 'Therapist is already serving a walk-in during this appointment'; end if;

  v_amount := round(v_service.price * 0.30);
  insert into public.bookings(
    client_id,client_name,client_phone,client_email,service_id,service_name,
    service_description,therapist_id,therapist_name,appointment_date,start_time,
    start_at,duration_minutes,total_amount
  ) values (
    auth.uid(),p_client_name,p_client_phone,p_client_email,v_service.id,v_service.name,
    v_service.description,v_therapist.id,v_therapist.name,p_appointment_date,
    p_start_time,p_start_at,v_service.duration_minutes,v_service.price
  ) returning * into v_booking;
  insert into public.payment_submissions(
    booking_id,submission_number,transaction_reference,amount,proof_path
  ) values (v_booking.id,1,p_transaction_reference,v_amount,p_proof_path)
  returning id into v_submission;
  insert into public.booking_activity(booking_id,actor_id,event)
    values (v_booking.id,auth.uid(),'booking_created'),(v_booking.id,auth.uid(),'proof_submitted');
  return v_booking.id;
end $$;

create or replace function public.start_walk_in(
  p_client_name text,p_client_phone text,p_service_id text,p_therapist_id uuid
)
returns uuid
language plpgsql security definer set search_path=public,auth
as $$
declare s public.services; t public.therapists; v_id uuid;
begin
  if public.current_app_role() not in ('admin','cashier') then
    raise exception 'Cashier access required';
  end if;
  select * into s from public.services where id=p_service_id and active;
  select * into t from public.therapists where id=p_therapist_id and active;
  if s.id is null or t.id is null then
    raise exception 'Choose an active service and therapist';
  end if;
  if not exists (
    select 1 from public.therapist_duty
    where therapist_id=t.id and work_date=(now() at time zone 'Asia/Manila')::date
  ) then raise exception 'Therapist is not on duty today'; end if;

  -- Use the same per-therapist lock as online booking creation to prevent
  -- simultaneous requests from reserving overlapping time.
  perform pg_advisory_xact_lock(hashtextextended(t.id::text,0));
  if exists (
    select 1 from public.bookings b
    where b.therapist_id=t.id and b.status<>'cancelled'
      and b.slot && tstzrange(now(),now()+make_interval(mins=>s.duration_minutes+5),'[)')
  ) then raise exception 'Therapist has an online booking during this service'; end if;
  if exists (
    select 1 from public.walk_ins w
    where w.therapist_id=t.id and w.completed_at>now()
  ) then raise exception 'Therapist is already serving a walk-in'; end if;
  insert into public.walk_ins(
    client_name,client_phone,service_id,service_name,therapist_id,therapist_name,
    duration_minutes,total_amount,created_by
  ) values (
    trim(p_client_name),coalesce(trim(p_client_phone),''),s.id,s.name,t.id,t.name,
    s.duration_minutes,s.price,auth.uid()
  ) returning id into v_id;
  return v_id;
end $$;

create or replace function public.available_therapists(
  p_date date,p_start_at timestamptz,p_duration integer,p_service_id text
)
returns table(id uuid,name text,specialty_service_id text,profile_image_path text)
language sql stable security definer set search_path=public,auth
as $$
  select t.id,t.name,t.specialty_service_id,t.profile_image_path
  from public.therapists t
  join public.therapist_duty d on d.therapist_id=t.id and d.work_date=p_date
  where t.active
    and exists (select 1 from public.services s where s.id=p_service_id and s.active)
    and not exists (
      select 1 from public.bookings b
      where b.therapist_id=t.id and b.status<>'cancelled'
        and b.slot && tstzrange(p_start_at,p_start_at+make_interval(mins=>p_duration),'[)')
    )
    and not exists (
      select 1 from public.walk_ins w
      where w.therapist_id=t.id and w.completed_at>now()
        and tstzrange(w.started_at,w.completed_at,'[)')
            && tstzrange(p_start_at,p_start_at+make_interval(mins=>p_duration),'[)')
    );
$$;

grant execute on function public.create_online_booking(text,uuid,date,text,timestamptz,text,text,text,text,text) to authenticated;
grant execute on function public.start_walk_in(text,text,text,uuid) to authenticated;
grant execute on function public.available_therapists(date,timestamptz,integer,text) to authenticated;
revoke execute on function public.create_online_booking(text,uuid,date,text,timestamptz,text,text,text,text,text) from public,anon;
revoke execute on function public.start_walk_in(text,text,text,uuid) from public,anon;
revoke execute on function public.available_therapists(date,timestamptz,integer,text) from public,anon;
