alter table public.bookings
  add column if not exists preparation_skipped_at timestamptz;

create or replace function public.skip_booking_preparation(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_booking public.bookings;
  v_now timestamptz;
begin
  if public.current_app_role() not in ('admin', 'cashier', 'therapist') then
    raise exception 'Staff access required';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;
  v_now := clock_timestamp();

  if public.current_app_role() = 'therapist' and not exists (
    select 1 from public.therapists t
    where t.auth_profile_id = auth.uid() and t.id = v_booking.therapist_id
  ) then
    raise exception 'This appointment is not assigned to you';
  end if;

  if v_booking.status <> 'inProgress' or v_booking.service_started_at is null then
    raise exception 'Preparation can only be skipped after the service has started';
  end if;

  if v_booking.preparation_skipped_at is not null then
    return;
  end if;

  if v_booking.service_started_at + interval '5 minutes' <= v_now then
    raise exception 'The preparation period has already ended';
  end if;

  update public.bookings
  set preparation_skipped_at = v_now, updated_at = v_now
  where id = v_booking.id;
end;
$$;

revoke all on function public.skip_booking_preparation(uuid) from public, anon;
grant execute on function public.skip_booking_preparation(uuid) to authenticated;
