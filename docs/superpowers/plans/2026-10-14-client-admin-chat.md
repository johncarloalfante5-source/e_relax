# Client to Admin Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add persistent, private, live text conversations between each client and the E-Relax admin.

**Architecture:** Supabase Postgres stores one conversation per client and immutable messages. RLS protects reads, and authenticated RPCs validate conversation creation, sends, and read-state updates. Flutter uses Supabase Realtime to refresh a shared chat thread and an admin inbox; the Gemini assistant stays independent.

**Tech Stack:** Flutter/Dart, Supabase Flutter, Postgres SQL, Supabase Auth/RLS, Supabase Realtime, GoRouter.

**Spec:** `docs/superpowers/specs/2026-10-14-client-admin-chat-design.md`

## Global Constraints

- Only client and admin roles participate; cashier and therapist roles have no conversation access.
- A client can access only their own thread; the admin can access the inbox and all threads.
- Message bodies are trimmed, text-only, and limited to 2,000 characters.
- The app uses the authenticated Supabase client and never embeds a service-role key.
- Gemini remains a separate assistant; direct messages are not sent to the chatbot.
- Version one excludes push notifications, attachments, voice, group chat, and message editing/deletion.

## Review Focus

- Spoofed conversation or sender IDs must be rejected by database authorization.
- Retrying after a response timeout must not duplicate a committed message.
- Realtime disconnects must reconcile persisted messages on reconnect.
- A client must not clear the admin's unread state or vice versa.
- Empty/whitespace and over-2,000-character bodies must be rejected consistently.

---

## File map

- Create `supabase/migrations/202610140004_client_admin_chat.sql` for tables, indexes, RLS, grants, triggers, and validated RPCs.
- Create `lib/models/client_admin_chat.dart` for conversation and message models.
- Create `lib/data/repositories/client_admin_chat_repository.dart` for authenticated database operations and Realtime subscriptions.
- Create `lib/presentation/client_admin_chat/client_admin_chat_thread_screen.dart` for the shared client/admin message thread.
- Create `lib/presentation/client_dashboard_screen/client_admin_chat_entry.dart` for the client dashboard entry and unread badge.
- Create `lib/presentation/admin_dashboard_screen/admin_client_chats_panel.dart` for the admin conversation inbox.
- Modify `lib/routes/app_routes.dart` for the client chat entry and role-gated thread route.
- Modify `lib/presentation/client_dashboard_screen/client_dashboard_screen.dart` to add a labelled Message Admin action while keeping the Gemini assistant separate.
- Modify `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart` to add the Customer Chats section, inbox, and live unread metric.

### Task 1: Secure Supabase schema and RPCs

**Files:**
- Create: `supabase/migrations/202610140004_client_admin_chat.sql`

**Interfaces:**
- `get_or_create_client_admin_conversation() returns uuid`: authenticated client-only; creates or returns the caller's single conversation.
- `send_client_admin_message(p_conversation_id uuid, p_message_id uuid, p_body text) returns setof public.client_admin_messages`: validates role, participant, sender, non-empty trimmed body, and 2,000-character limit; uses `p_message_id` as an idempotency key.
- `mark_client_admin_conversation_read(p_conversation_id uuid) returns void`: validates participant and updates only the caller's own read timestamp.
- `get_admin_client_chat_inbox() returns table(conversation_id uuid, client_id uuid, client_name text, latest_body text, latest_message_at timestamptz, unread_count bigint)`: admin-only inbox summary.

- [x] Add `client_admin_conversations` with one unique row per `client_id`, timestamps, and separate client/admin last-read timestamps.
- [x] Add `client_admin_messages` with UUID idempotency key, conversation FK, sender FK, body, and created timestamp; add indexes for ordered thread reads and unread queries.
- [x] Enable RLS, revoke broad table writes, grant authenticated reads, and add policies that limit client reads to their own conversation and admin reads to the admin role.
- [x] Add the four authenticated RPCs above. Use `security definer` only with a fixed search path, explicit `auth.uid()`/role checks, and execute grants limited to `authenticated`.
- [x] Add a trigger or validated send operation to advance conversation `updated_at`; add the messages table to `supabase_realtime` if the publication exists.
- [x] Review migration SQL against the Review Focus and the project's existing migration conventions. Do not apply it to the hosted project as part of this task; deployment remains a separate user-run `supabase db push` step.

### Task 2: Chat models and repository

**Files:**
- Create: `lib/models/client_admin_chat.dart`
- Create: `lib/data/repositories/client_admin_chat_repository.dart`

**Interfaces:**
- `ClientAdminConversation.fromJson(Map<String, dynamic>)` parses inbox/thread metadata.
- `ClientAdminMessage.fromJson(Map<String, dynamic>)` parses a stored message.
- `ClientAdminChatRepository.getOrCreateClientConversation() -> Future<String>` calls the client-only RPC.
- `ClientAdminChatRepository.fetchMyExistingConversation() -> Future<ClientAdminConversation?>` loads the client's thread without creating one.
- `ClientAdminChatRepository.countUnreadClientMessages(ClientAdminConversation conversation) -> Future<int>` counts admin messages after the client's last-read timestamp.
- `ClientAdminChatRepository.fetchMessages(String conversationId, {int limit = 50, DateTime? before}) -> Future<List<ClientAdminMessage>>` returns chronological messages, paging older rows as needed.
- `ClientAdminChatRepository.sendMessage({required String conversationId, required String messageId, required String body}) -> Future<ClientAdminMessage>` calls the validated send RPC and resolves duplicate retries by message ID.
- `ClientAdminChatRepository.markRead(String conversationId) -> Future<void>` calls the validated read RPC.
- `ClientAdminChatRepository.fetchAdminInbox() -> Future<List<ClientAdminConversation>>` calls the admin-only inbox RPC.
- `watchMessages(String conversationId, VoidCallback onChange)` and `watchInbox(VoidCallback onChange)` return removable Supabase Realtime channels.

- [x] Add immutable model fields and JSON parsing for conversation metadata and message records.
- [x] Implement methods using `SupabaseClientProvider.client`; rely on the current auth session and do not accept a sender/client ID as authorization.
- [x] Subscribe to message changes filtered by conversation ID; subscribe to message and conversation changes for the admin inbox; remove each channel on disposal.
- [x] Load client unread state from the existing conversation only, then refresh its count on Realtime events.
- [x] After a Realtime event or reconnect, refetch canonical rows from Postgres so event loss cannot permanently desynchronize the UI.

### Task 3: Shared conversation thread

**Files:**
- Create: `lib/presentation/client_admin_chat/client_admin_chat_thread_screen.dart`

**Interfaces:**
- `ClientAdminChatThreadScreen({required String conversationId})` determines client/admin presentation from the authenticated profile; database authorization remains authoritative.

- [x] Load recent messages, subscribe to the thread, and mark the current viewer's unread messages read when the thread opens and receives new messages.
- [x] Render chronological client/admin message bubbles, timestamps, loading/empty states, and a text composer with a 2,000-character limit.
- [x] Generate a message UUID before sending and reuse it for retries; preserve the draft and show a retryable error if sending fails.
- [x] Dispose the Realtime channel and text controller when the screen closes; reload messages after reconnect.

### Task 4: Client entry and routing

**Files:**
- Create: `lib/presentation/client_dashboard_screen/client_admin_chat_entry.dart`
- Modify: `lib/routes/app_routes.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_dashboard_screen.dart`

**Interfaces:**
- `AppRoutes.clientAdminChatThreadBase` is `/client-admin-chat`; the thread route is parameterized by conversation UUID and allowed only for client/admin roles.

- [x] Add the route guards: clients may open their own chat flow/thread; admins may open thread routes from their inbox; cashier and therapist routes redirect to their role home.
- [x] Add a labelled Message Admin dashboard action without replacing or overlapping the Gemini Assistant or Book Now actions.
- [x] Show an unread badge based on the client's own existing thread; do not create a conversation just to display a zero-count badge.
- [x] On tap, call `getOrCreateClientConversation()` and open the shared thread with the returned conversation ID.

### Task 5: Admin live inbox

**Files:**
- Create: `lib/presentation/admin_dashboard_screen/admin_client_chats_panel.dart`
- Modify: `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart`

**Interfaces:**
- `AdminClientChatsPanel(onOpenConversation: ValueChanged<String>)` loads the inbox and opens a shared thread by conversation ID.

- [x] Add a Customer Chats admin section and replace the placeholder with an inbox showing client name, latest message/time, and unread count.
- [x] Subscribe to inbox changes, refresh the inbox from Postgres after each event, and open the shared thread when an inbox row is selected.
- [x] Replace the hard-coded Open chats metric with the count of conversations containing unread client messages and link it to the Customer Chats section.
- [x] Keep the inbox navigable at laptop and narrow/mobile widths; show useful loading, empty, and retry states.

### Task 6: Integration handoff

**Files:**
- Modify only if needed: files listed in Tasks 2–5.

- [x] Review client/admin/cashier/therapist access paths against the acceptance criteria and confirm no Gemini code receives direct messages.
- [x] Inspect the final migration and Flutter changes. Do not add/run automated tests or analyzer/build checks unless the user asks for verification.
- [x] Provide the user the migration deployment command `npx --yes supabase db push`, then the Flutter Chrome/mobile run commands. Do not claim the remote schema is deployed until the user applies the migration.

## Self-review

- **Spec coverage:** persistent conversations, client/admin roles, RLS, realtime, unread counts, retry/idempotency, client UI, admin inbox, Gemini separation, and migration rollout are assigned to Tasks 1–6.
- **Step scan:** each task's steps are bounded by a file/interface and a visible result; all RPC/repository names are consistent across tasks.
- **Type consistency:** chat IDs and message IDs are UUID strings in Flutter and UUIDs in SQL; timestamps are UTC `timestamptz`; unread counts are integer-valued.
- **Review Focus:** all five listed failure/input classes are covered by database constraints/RPC validation; verification commands are deferred because the current instruction says not to add/run tests unless requested.
- **Proportion:** six implementation tasks cover the data layer, shared thread, client entry, and admin inbox without changing the existing Gemini subsystem.

