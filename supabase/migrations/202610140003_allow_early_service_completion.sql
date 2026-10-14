-- Staff may complete an in-progress online service at any time. The timer
-- remains informational and no longer blocks the status transition.
create or replace function public.transition_booking(
  p_booking_id uuid,p_status text,p_reason text default null
)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare b public.bookings; v_event text;
begin
  select * into b from public.bookings where id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if public.current_app_role() not in ('admin','cashier','therapist') then
    raise exception 'Staff access required';
  end if;
  if public.current_app_role()='therapist' and not exists(
    select 1 from public.therapists t
    where t.auth_profile_id=auth.uid() and t.id=b.therapist_id
  ) then raise exception 'This appointment is not assigned to you'; end if;

  if p_status='confirmed' then
    if b.status not in ('pendingPayment','confirmed') then
      raise exception 'Only a payment-pending booking can be confirmed';
    end if;
    if not exists(
      select 1 from public.payment_submissions s
      where s.booking_id=b.id and s.status='Verified'
    ) then raise exception 'Payment must be verified before confirmation'; end if;
  elsif p_status='checkedIn' then
    if b.status <> 'confirmed' then
      raise exception 'Only a confirmed booking can be checked in';
    end if;
  elsif p_status='inProgress' then
    if b.status <> 'checkedIn' then
      raise exception 'Check in before starting service';
    end if;
  elsif p_status='completed' then
    if b.status <> 'inProgress' then
      raise exception 'Only an in-progress service can be completed';
    end if;
  elsif p_status='cancelled' then
    if b.status in ('completed','cancelled') or trim(coalesce(p_reason,''))='' then
      raise exception 'Cancellation requires an active booking and a reason';
    end if;
  else
    raise exception 'Unsupported booking status';
  end if;

  if b.status=p_status then return; end if;
  v_event := case p_status
    when 'confirmed' then 'booking_confirmed'
    when 'checkedIn' then 'client_checked_in'
    when 'inProgress' then 'service_started'
    when 'completed' then 'service_completed'
    else 'booking_cancelled'
  end;
  update public.bookings set
    status=p_status,
    checked_in_at=case when p_status='checkedIn' then now() else checked_in_at end,
    service_started_at=case when p_status='inProgress' then now() else service_started_at end,
    service_completed_at=case when p_status='completed' then now() else service_completed_at end,
    cancellation_reason=case when p_status='cancelled' then trim(p_reason) else cancellation_reason end,
    cancelled_at=case when p_status='cancelled' then now() else cancelled_at end,
    cancelled_by=case when p_status='cancelled' then auth.uid() else cancelled_by end,
    updated_at=now()
  where id=b.id;
  insert into public.booking_activity(booking_id,actor_id,event,note)
    values(
      b.id,auth.uid(),v_event,
      case when p_status='cancelled' then trim(p_reason) else null end
    );
  if p_status in ('confirmed','cancelled') then
    insert into public.notifications(user_id,booking_id,event_key,title,message)
    values(
      b.client_id,b.id,p_status||':'||b.id::text,
      case when p_status='confirmed' then 'Appointment confirmed' else 'Appointment cancelled' end,
      case when p_status='confirmed'
        then b.service_name||' is confirmed for '||b.appointment_date::text||' at '||b.start_time||'.'
        else 'Appointment cancelled: '||trim(p_reason)
      end
    ) on conflict(user_id,event_key) do nothing;
  end if;
end $$;

grant execute on function public.transition_booking(uuid,text,text) to authenticated;
revoke execute on function public.transition_booking(uuid,text,text) from public,anon;
