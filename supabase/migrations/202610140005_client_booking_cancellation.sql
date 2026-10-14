-- Clients may cancel only their own confirmed booking before staff check-in.
-- A verified down payment remains captured; this function issues no refund.
create or replace function public.cancel_client_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings%rowtype;
  v_note text := 'Cancelled by client. Down payment is non-refundable; no refund issued.';
begin
  if auth.uid() is null then
    raise exception 'Sign in required';
  end if;

  if public.current_app_role() is distinct from 'client' then
    raise exception 'Client access required';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found or v_booking.client_id <> auth.uid() then
    raise exception 'Booking not found';
  end if;

  if v_booking.status <> 'confirmed'
    or not exists (
      select 1 from public.payment_submissions s
      where s.booking_id = v_booking.id and s.status = 'Verified'
    )
    or not exists (
      select 1 from public.payment_transactions t
      where t.source_type = 'booking_deposit' and t.source_id = v_booking.id
    ) then
    raise exception 'A verified down payment is required before cancellation';
  end if;

  update public.bookings
  set status = 'cancelled',
      cancellation_reason = v_note,
      cancelled_at = now(),
      cancelled_by = auth.uid(),
      updated_at = now()
  where id = v_booking.id;

  insert into public.booking_activity(booking_id, actor_id, event, note)
  values (v_booking.id, auth.uid(), 'booking_cancelled', v_note);

  insert into public.notifications(user_id, booking_id, event_key, title, message)
  values (
    v_booking.client_id,
    v_booking.id,
    'booking_cancelled:' || v_booking.id::text,
    'Booking cancelled',
    v_booking.service_name || ' was cancelled. The down payment is non-refundable; no refund was issued.'
  )
  on conflict (user_id, event_key) do nothing;
end;
$$;

revoke all on function public.cancel_client_booking(uuid) from public, anon;
grant execute on function public.cancel_client_booking(uuid) to authenticated;
