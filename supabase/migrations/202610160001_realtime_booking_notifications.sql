-- Persist the booking lifecycle notices that were previously missing.
-- Existing RPCs remain responsible for payment, confirmation, and cancellation
-- notices; event keys are shared where needed so this trigger is idempotent.
create or replace function public.notify_booking_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin record;
  v_event_key text;
  v_title text;
  v_message text;
begin
  if tg_op = 'INSERT' then
    for v_admin in select id from public.profiles where role = 'admin' loop
      insert into public.notifications(user_id, booking_id, event_key, title, message)
      values (
        v_admin.id,
        new.id,
        'new_booking:' || new.id::text,
        'New online booking',
        new.client_name || ' booked ' || new.service_name || ' for ' || new.appointment_date::text || ' at ' || new.start_time || '.'
      ) on conflict (user_id, event_key) do nothing;
    end loop;
    return new;
  end if;

  if old.status is not distinct from new.status then
    return new;
  end if;

  if new.status = 'checkedIn' then
    v_event_key := 'booking_checked_in:' || new.id::text;
    v_title := 'You have checked in';
    v_message := 'You are checked in for ' || new.service_name || '.';
  elsif new.status = 'inProgress' then
    v_event_key := 'booking_service_started:' || new.id::text;
    v_title := 'Your service has started';
    v_message := 'Your ' || new.service_name || ' service is now in progress.';
  elsif new.status = 'completed' then
    v_event_key := 'booking_service_completed:' || new.id::text;
    v_title := 'Your service is complete';
    v_message := 'Your ' || new.service_name || ' service has been completed.';
  elsif new.status = 'cancelled' and new.cancelled_by = new.client_id then
    -- The client cancellation RPC already writes the matching client notice.
    -- Notify every admin, but never expose client cancellations to cashiers.
    for v_admin in select id from public.profiles where role = 'admin' loop
      insert into public.notifications(user_id, booking_id, event_key, title, message)
      values (
        v_admin.id,
        new.id,
        'client_cancelled:' || new.id::text,
        'Client cancelled a booking',
        new.client_name || ' cancelled ' || new.service_name || ' for ' || new.appointment_date::text || ' at ' || new.start_time || '.'
      ) on conflict (user_id, event_key) do nothing;
    end loop;
    return new;
  else
    return new;
  end if;

  insert into public.notifications(user_id, booking_id, event_key, title, message)
  values (new.client_id, new.id, v_event_key, v_title, v_message)
  on conflict (user_id, event_key) do nothing;
  return new;
end;
$$;

revoke all on function public.notify_booking_lifecycle() from public, anon, authenticated;

create trigger bookings_notify_after_insert
after insert on public.bookings
for each row execute function public.notify_booking_lifecycle();

create trigger bookings_notify_status_change
after update of status on public.bookings
for each row execute function public.notify_booking_lifecycle();
