-- Cashiers may collect a verified online booking's remaining balance from
-- check-in onward, without waiting for the service to finish.
create or replace function public.collect_online_balance(p_booking_id uuid,p_method text)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare b public.bookings; v_paid numeric(12,2); v_amount numeric(12,2); v_key text;
begin
  if public.current_app_role() not in ('admin','cashier') then
    raise exception 'Cashier access required';
  end if;
  if p_method not in ('Cash','Card','GCash') then
    raise exception 'Choose a valid payment method';
  end if;
  select * into b from public.bookings where id=p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if b.status not in ('checkedIn','inProgress','completed') then
    raise exception 'Check in the client before collecting the balance';
  end if;
  if not exists (
    select 1 from public.payment_submissions s
    where s.booking_id=b.id and s.status='Verified'
  ) then raise exception 'A verified online down payment is required'; end if;

  select coalesce(sum(amount),0) into v_paid
  from public.payment_transactions
  where source_id=b.id and source_type in ('booking_deposit','booking_balance');
  v_amount := b.total_amount-v_paid;
  if v_amount <= 0 then return; end if;
  v_key := 'balance:'||b.id::text;
  insert into public.payment_transactions(source_type,source_id,amount,method,actor_id,idempotency_key)
    values('booking_balance',b.id,v_amount,p_method,auth.uid(),v_key)
    on conflict(idempotency_key) do nothing;
  insert into public.booking_activity(booking_id,actor_id,event,note)
    values(b.id,auth.uid(),'balance_collected',p_method);
  insert into public.notifications(user_id,booking_id,event_key,title,message)
    values(b.client_id,b.id,'balance_collected:'||b.id::text,'Balance paid',
      'Your remaining appointment balance has been collected.')
    on conflict(user_id,event_key) do nothing;
end $$;

grant execute on function public.collect_online_balance(uuid,text) to authenticated;
revoke execute on function public.collect_online_balance(uuid,text) from public,anon;
