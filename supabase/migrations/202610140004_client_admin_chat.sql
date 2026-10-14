-- Persistent one-to-one client/admin support conversations.

create table public.client_admin_conversations (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null unique references public.profiles(id) on delete cascade,
  client_last_read_at timestamptz,
  admin_last_read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.client_admin_messages (
  id uuid primary key,
  conversation_id uuid not null references public.client_admin_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index client_admin_messages_thread_order_idx
  on public.client_admin_messages(conversation_id, created_at, id);
create index client_admin_messages_unread_idx
  on public.client_admin_messages(conversation_id, sender_id, created_at);

alter table public.client_admin_conversations enable row level security;
alter table public.client_admin_messages enable row level security;

revoke all on public.client_admin_conversations, public.client_admin_messages
  from public, anon, authenticated;
grant select on public.client_admin_conversations, public.client_admin_messages
  to authenticated;

create policy "client or admin reads chat conversations"
  on public.client_admin_conversations for select to authenticated
  using (
    public.current_app_role() = 'admin'
    or (client_id = auth.uid() and public.current_app_role() = 'client')
  );

create policy "client or admin reads chat messages"
  on public.client_admin_messages for select to authenticated
  using (
    public.current_app_role() = 'admin'
    or (
      public.current_app_role() = 'client'
      and exists (
        select 1
        from public.client_admin_conversations c
        where c.id = conversation_id and c.client_id = auth.uid()
      )
    )
  );

create or replace function public.get_or_create_client_admin_conversation()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_conversation_id uuid;
begin
  if v_user_id is null or public.current_app_role() <> 'client' then
    raise exception 'Client access required';
  end if;

  insert into public.client_admin_conversations(client_id)
  values (v_user_id)
  on conflict (client_id) do nothing;

  select id into v_conversation_id
  from public.client_admin_conversations
  where client_id = v_user_id;

  return v_conversation_id;
end;
$$;

create or replace function public.send_client_admin_message(
  p_conversation_id uuid,
  p_message_id uuid,
  p_body text
)
returns setof public.client_admin_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_role public.app_role := public.current_app_role();
  v_client_id uuid;
  v_body text := btrim(coalesce(p_body, ''));
  v_message public.client_admin_messages%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in required';
  end if;
  if p_message_id is null or p_conversation_id is null then
    raise exception 'Message and conversation IDs are required';
  end if;
  if length(v_body) < 1 or length(v_body) > 2000 then
    raise exception 'Message must contain 1 to 2000 characters';
  end if;

  select client_id into v_client_id
  from public.client_admin_conversations
  where id = p_conversation_id;
  if not found then
    raise exception 'Conversation unavailable';
  end if;
  if not (
    (v_role = 'client' and v_client_id = v_user_id)
    or v_role = 'admin'
  ) then
    raise exception 'Conversation unavailable';
  end if;

  insert into public.client_admin_messages(id, conversation_id, sender_id, body)
  values (p_message_id, p_conversation_id, v_user_id, v_body)
  on conflict (id) do nothing
  returning * into v_message;

  if not found then
    select * into v_message
    from public.client_admin_messages
    where id = p_message_id;
    if v_message.conversation_id is distinct from p_conversation_id
      or v_message.sender_id is distinct from v_user_id
      or v_message.body is distinct from v_body then
      raise exception 'Message ID already used';
    end if;
    return next v_message;
    return;
  end if;

  update public.client_admin_conversations
  set updated_at = now()
  where id = p_conversation_id;

  return next v_message;
end;
$$;

create or replace function public.mark_client_admin_conversation_read(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_role public.app_role := public.current_app_role();
  v_client_id uuid;
begin
  if v_user_id is null then
    raise exception 'Sign in required';
  end if;

  select client_id into v_client_id
  from public.client_admin_conversations
  where id = p_conversation_id;
  if not found then
    raise exception 'Conversation unavailable';
  end if;

  if v_role = 'admin' then
    update public.client_admin_conversations
    set admin_last_read_at = now()
    where id = p_conversation_id;
  elsif v_role = 'client' and v_client_id = v_user_id then
    update public.client_admin_conversations
    set client_last_read_at = now()
    where id = p_conversation_id;
  else
    raise exception 'Conversation unavailable';
  end if;
end;
$$;

create or replace function public.get_admin_client_chat_inbox()
returns table (
  conversation_id uuid,
  client_id uuid,
  client_name text,
  latest_body text,
  latest_message_at timestamptz,
  unread_count bigint
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.current_app_role() <> 'admin' then
    raise exception 'Admin access required';
  end if;

  return query
  select
    c.id,
    c.client_id,
    coalesce(p.display_name, 'Client'),
    latest.body,
    latest.created_at,
    (
      select count(*)
      from public.client_admin_messages incoming
      where incoming.conversation_id = c.id
        and incoming.sender_id = c.client_id
        and (
          c.admin_last_read_at is null
          or incoming.created_at > c.admin_last_read_at
        )
    )
  from public.client_admin_conversations c
  join public.profiles p on p.id = c.client_id
  left join lateral (
    select m.body, m.created_at
    from public.client_admin_messages m
    where m.conversation_id = c.id
    order by m.created_at desc, m.id desc
    limit 1
  ) latest on true
  order by coalesce(latest.created_at, c.updated_at) desc;
end;
$$;

revoke all on function public.get_or_create_client_admin_conversation()
  from public, anon;
revoke all on function public.send_client_admin_message(uuid, uuid, text)
  from public, anon;
revoke all on function public.mark_client_admin_conversation_read(uuid)
  from public, anon;
revoke all on function public.get_admin_client_chat_inbox()
  from public, anon;
grant execute on function public.get_or_create_client_admin_conversation()
  to authenticated;
grant execute on function public.send_client_admin_message(uuid, uuid, text)
  to authenticated;
grant execute on function public.mark_client_admin_conversation_read(uuid)
  to authenticated;
grant execute on function public.get_admin_client_chat_inbox()
  to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'client_admin_conversations'
    ) then
      alter publication supabase_realtime
        add table public.client_admin_conversations;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'client_admin_messages'
    ) then
      alter publication supabase_realtime
        add table public.client_admin_messages;
    end if;
  end if;
end;
$$;
