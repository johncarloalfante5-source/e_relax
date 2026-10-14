# Client to Admin Chat Design

## Status

Design specification for review. No direct-message implementation or database
migration has been created. Implementation planning starts only after this
specification is reviewed and approved.

## Goal

Let signed-in clients send persistent messages directly to the E-Relax admin,
and let the admin read and reply to each client's private conversation from the
operations dashboard. Keep the Gemini assistant as a separate feature.

## Approved scope

- One private conversation per client, shared with the single admin role.
- A client can start the conversation from the client dashboard and continue
  the same thread on another signed-in device.
- Clients can read their thread and send text messages. They cannot view or
  address another client's thread.
- The admin gets a live inbox, can open any client's conversation and reply,
  and sees unread counts/indicators.
- New messages appear live in an open client or admin thread using Supabase
  Realtime. Unread indicators update while the relevant app screen is active.
- The Gemini assistant remains separate and available from its existing entry
  point. The direct-contact entry must be clearly labelled "Message Admin".
- Messages are text-only, length-limited, and persist across sign-ins/devices.
- Sending errors retain the draft/message and show an explicit retry state.
- No push notifications, attachments, voice messages, chatbot handoff, group
  chats, or booking changes in this release.

## Current project findings

- The app already uses Supabase Auth, Postgres, RLS, and Supabase Realtime for
  shared application data.
- `public.current_app_role()` is available for database role checks. The admin
  role is represented in `public.profiles`; client accounts are separately
  authenticated.
- The existing client chat screen invokes the `client-chatbot` Edge Function
  and keeps Gemini conversation messages only in view state. It is not a
  human-support channel and must not be repurposed as one.
- The admin dashboard's "Customer chats" panel currently displays a
  disconnected placeholder and its "Open chats" metric is hard-coded to zero.
- Database schema changes are maintained in `supabase/migrations/` and applied
  to the hosted project using `npx --yes supabase db push`.

## Architecture and data flow

### Database

Add two tables in a new migration:

1. `public.client_admin_conversations`
   - `id uuid primary key`
   - `client_id uuid not null references public.profiles(id)` with a unique
     constraint, enforcing one thread per client
   - `created_at` and `updated_at` timestamps
   - `client_last_read_at` and `admin_last_read_at` timestamps for unread
     calculation
2. `public.client_admin_messages`
   - `id uuid primary key`
   - `conversation_id uuid not null` referencing its conversation
   - `sender_id uuid not null` referencing `public.profiles(id)`
   - `body text not null`, trimmed and limited to 2,000 characters
   - `created_at timestamptz not null`

Add indexes for conversation lookup/order and unread-count queries. Add the
messages table to the `supabase_realtime` publication using the same guarded
migration pattern used by the existing migrations.

### Authorization

- Enable RLS on both chat tables.
- A client may select only their conversation and its messages, with ownership
  derived from `auth.uid()` rather than a client-supplied identity.
- Only a user whose database role is `admin` may list all conversations and
  read/send messages across clients. Cashier and therapist roles do not receive
  access in this version.
- A message insert must require `sender_id = auth.uid()` and verify the sender
  is either the owning client or an admin. Clients cannot set another sender
  or target another client's conversation.
- Read-state updates use narrowly scoped database operations that validate
  the authenticated reader and change only that reader's last-read timestamp;
  clients cannot mark admin messages read on behalf of the admin (and vice
  versa).
- No Supabase service-role key is included in Flutter. No message content or
  private conversation data is sent to Gemini.

### Flutter repositories and realtime

- Add a focused repository for create-or-fetch-own-conversation, paginated
  message loading, sending, marking the current user's conversation read, and
  subscribing/unsubscribing to Supabase Realtime changes.
- Use the authenticated Supabase Flutter client. Do not accept a user ID from
  the UI as authority; the database policies remain the security boundary.
- Refresh/reconcile messages from Postgres after realtime notifications so
  reconnects do not lose data. Prevent duplicate sends when a retry follows a
  timeout by assigning a client-generated message UUID before submission.
- Dispose realtime subscriptions when a screen closes or the session changes.

## User experience

### Client

- Keep the existing Gemini Assistant button separate.
- Add a labelled "Message Admin" entry on the client dashboard with an unread
  badge when the admin has replied since the client last opened the thread.
- Opening it creates or loads the signed-in client's single thread, displays
  chronological message bubbles, and offers a text composer/send action.
- Show loading, empty-thread, offline/send failure, retry, and signed-out
  states. Keep a failed message editable or retryable without silently losing
  its text.

### Admin

- Replace the disconnected "Customer chats" placeholder with an inbox listing
  clients, latest message/time, and unread count.
- Selecting a row opens the conversation in the dashboard and marks incoming
  client messages read for the admin.
- The existing "Open chats" metric reports conversations with unread client
  messages, rather than a hard-coded zero.
- Keep the inbox usable on the laptop Chrome layout and responsive on narrower
  screens.

## Failure behavior

- Missing or expired session: return to sign-in or show a clear sign-in prompt;
  do not expose any conversation data.
- Realtime disconnect: show the last loaded thread, attempt resubscription,
  and reconcile from Postgres when connectivity returns.
- Message insert failure: keep the draft and show a retry action. Use the same
  message UUID when retrying so a committed send with a lost response is not
  duplicated.
- Empty conversation: show a simple invitation to message the admin.
- Unauthorized access: surface a generic access error without revealing
  whether another client's conversation exists.

## Out of scope

- Push notifications while the app is closed.
- Attachments, voice/video, group conversations, and staff assignment/routing.
- Cashier/therapist participation or access to private client conversations.
- Gemini-generated replies, chatbot handoff, message search, and analytics.
- Deleting/editing sent messages or automatic transcript expiry.

## Acceptance criteria

1. A client can start a conversation and see the same persisted history after
   signing in on another device.
2. A client can send a message and an open admin inbox/thread receives it
   without manual refresh; an open client thread receives admin replies too.
3. The admin inbox shows the correct client, latest message, and unread state;
   opening a thread clears unread state for that reader.
4. A client cannot select, read, write to, or infer another client's thread by
   changing request IDs or calling PostgREST directly.
5. Non-admin staff cannot list or read all client conversations.
6. Message size limits, sign-out, network interruption, reconnect, and retry
   behavior produce clear UI states and do not duplicate messages.
7. The Gemini assistant continues to work separately, and direct chat never
   includes message history in chatbot requests.
8. The client experience works on mobile and Chrome; the admin inbox works on
   laptop Chrome and remains usable at narrow widths.

## Verification and rollout plan

- Review migration SQL and exercise RLS as client A, client B, admin, cashier,
  and therapist roles before enabling the UI.
- Verify client A cannot query client B's conversation/messages and cannot
  spoof sender identity, recipient, or read state.
- Verify the admin can list/reply, and unread state changes only for the reader
  whose thread is opened.
- Exercise realtime send/receive, disconnect/reconnect, duplicate retry,
  expired session, and mobile/web layouts.
- Apply the reviewed migration with `npx --yes supabase db push`, then rebuild
  and run the Flutter app on the laptop and client device. No Gemini Edge
  Function deployment is required for direct messaging.
