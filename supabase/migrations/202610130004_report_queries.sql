create or replace function public.report_sales(p_from timestamptz,p_to timestamptz)
returns table(captured_at timestamptz, amount numeric, source_type text, method text, source_id uuid)
language plpgsql stable security invoker set search_path=public,auth
as $$
begin
  if public.current_app_role() not in ('admin','cashier') then raise exception 'Staff access required'; end if;
  return query select pt.captured_at,pt.amount,pt.source_type,pt.method,pt.source_id
   from public.payment_transactions pt where pt.captured_at>=p_from and pt.captured_at<p_to order by pt.captured_at;
end $$;

create or replace function public.report_completed_services(p_from timestamptz,p_to timestamptz)
returns table(completed_at timestamptz,service_id text,service_name text,source_type text,source_id uuid)
language plpgsql stable security invoker set search_path=public,auth
as $$
begin
  if public.current_app_role() not in ('admin','cashier') then raise exception 'Staff access required'; end if;
  return query
   select b.service_completed_at,b.service_id,b.service_name,'online'::text,b.id
    from public.bookings b where b.status='completed' and b.service_completed_at>=p_from and b.service_completed_at<p_to
   union all
   select w.completed_at,w.service_id,w.service_name,'walk_in'::text,w.id
    from public.walk_ins w where w.completed_at<=now() and w.completed_at>=p_from and w.completed_at<p_to;
end $$;
grant execute on function public.report_sales(timestamptz,timestamptz),public.report_completed_services(timestamptz,timestamptz) to authenticated;
revoke execute on function public.report_sales(timestamptz,timestamptz),public.report_completed_services(timestamptz,timestamptz) from public,anon;

-- Enable Postgres Changes where the hosted Supabase Realtime publication exists.
do $$
declare table_name text;
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach table_name in array array['profiles','services','therapists','therapist_duty','therapist_directory_events','bookings','payment_submissions','booking_activity','notifications','payment_transactions','walk_ins'] loop
      if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=table_name) then
        execute format('alter publication supabase_realtime add table public.%I',table_name);
      end if;
    end loop;
  end if;
end $$;
