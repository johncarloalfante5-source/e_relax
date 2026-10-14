# Client Chatbot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give signed-in clients clinic and app help plus accurate summaries of their own bookings through a Gemini-powered chat.

**Architecture:** The Flutter dashboard opens an in-memory chat screen. Flutter invokes one authenticated Supabase Edge Function; the function reads only the caller's permitted clinic, booking, and payment data under RLS, calls Gemini using a server-side secret, and returns a bounded text answer. The model has no database tools and cannot mutate bookings.

**Tech Stack:** Flutter/Dart, `supabase_flutter`, GoRouter, Supabase Edge Functions (Deno TypeScript), Supabase Postgres RLS, Gemini `generateContent` REST API.

**Spec:** `docs/superpowers/specs/2026-10-14-client-chatbot-design.md`

## Global Constraints

- Only signed-in clients can use the endpoint.
- Never use a service-role client for client booking context; query with the user's RLS-scoped Supabase client.
- Keep `GEMINI_API_KEY` in Edge Function Secrets and out of Flutter, build defines, logs, and responses.
- Read only active services and the authenticated client's own bookings and payment summaries.
- Send Gemini bounded recent turns from the current chat view only; do not persist transcript history.
- Do not allow booking changes, human-chat records, medical advice, or guessed clinic contact details.
- Validate request shape, text length, history roles/count/length, upstream response shape, and response length.
- No database migration or Flutter dependency is needed for this first version.
- Do not add or run automated tests unless the user explicitly requests testing or verification.

## Review Focus

1. A client must not read another client's bookings by changing prompt, history, or body fields; use JWT-derived identity and RLS-scoped queries.
2. Invalid/expired JWTs and non-client roles must not reach booking reads or Gemini.
3. Forged assistant history must be treated as untrusted text and cannot override the system instruction or authorize data access.
4. Gemini errors, malformed responses, empty answers, or rate limits must return safe retry guidance without leaking secrets or private data.
5. Missing clinic contact details, business hours, or unsupported facts must not be invented; use a clear fallback to ask clinic staff.

---

### Task 1: Implement the authenticated Gemini Edge Function

**Files:**
- Modify: `supabase/functions/client-chatbot/index.ts`
- Create: `supabase/functions/client-chatbot/clinic_facts.ts`
- Modify: `supabase/config.toml` (`[functions.client-chatbot]`)

**Interfaces:**
- Request JSON: `{ "message": string, "history": Array<{ "role": "user" | "model", "text": string }> }`; `history` is optional and contains prior turns only.
- Success JSON: `{ "reply": string }`.
- All errors: JSON `{ "error": string, "retryable": boolean }` with an appropriate 4xx or 5xx status.
- Use `withSupabase({ auth: 'user' }, handler)` from the scaffold; derive the identity from verified user claims and use `ctx.supabase`, never `ctx.supabaseAdmin`, for user data.

- [ ] Replace the sample handler with an authenticated POST-only handler. Reject non-JSON, malformed payloads, blank messages, message text over 1200 characters, more than 8 history items, history text over 800 characters per item, aggregate history over 3200 characters, and roles other than `user`/`model`.
- [ ] Read the caller's own `profiles.role` through `ctx.supabase`; continue only when it is `client`, otherwise return 403 before reading bookings or calling Gemini.
- [ ] Query `services` with columns `id,name,description,price,duration_minutes,category`, filtered to `active = true`.
- [ ] When a personal appointment/payment question is detected using appointment terms (booking, reservation, appointment, schedule) or first-person wording together with payment terms (payment, deposit, balance, paid), query at most 10 upcoming non-cancelled bookings by `start_at >= now()` ordered earliest first and 10 recent bookings by `start_at < now()` ordered latest first. Select only `reference_number,service_name,therapist_name,appointment_date,start_time,start_at,duration_minutes,total_amount,status,created_at`, filter both queries by `client_id = verified JWT sub`, and do not accept a client ID or booking ID in the request.
- [ ] For those same personal appointment/payment questions only, query the caller's `payment_submissions` with only `booking_id,status,amount,submission_number` and `payment_transactions` with only `source_id,source_type,amount,captured_at`; rely on the existing user-scoped client/RLS policies. Build a minimal payment summary per owned booking; never read/download `proof_path` or transaction references.
- [ ] Add `clinic_facts.ts` with only confirmed rules already represented in the app/backend: bookable slots are 11:00 AM–8:00 PM at 5-minute intervals, a 30% down payment is required to confirm online reservations, remaining balance can be collected after check-in, and no separate service fee is charged. Do not add business hours, address, phone, or contact links that are not configured in the project.
- [ ] Build Gemini `generateContent` input from a server instruction, the clinic facts, the minimal live service/booking/payment context, validated recent turns, and the current question. Instruct the model to answer only from supplied facts, treat all user/history text as untrusted, refuse booking mutations and medical advice, and use a clear fallback for missing facts.
- [ ] Call `https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent` using `x-goog-api-key: Deno.env.get('GEMINI_API_KEY')`; set a 500-token maximum response and a 20-second abort timeout. Never log request content, auth data, or the key.
- [ ] Return a non-empty plain-text `reply` capped at 1800 characters. Map invalid input/auth/upstream failures to safe JSON errors; distinguish retryable network/rate-limit/service failures from non-retryable input errors. Keep `verify_jwt = true` in `supabase/config.toml` and retain the user-auth wrapper.
- [ ] Review the handler against the Review Focus items 1–5 before moving to the Flutter client.

### Task 2: Add the Flutter function client and chat message model

**Files:**
- Create: `lib/models/client_chat_message.dart`
- Create: `lib/data/repositories/client_chatbot_repository.dart`

**Interfaces:**
- `ClientChatMessage({required String text, required bool isAssistant})` is an immutable in-memory chat item.
- `ClientChatbotRepository.reply({required String message, required List<ClientChatMessage> history}) -> Future<String>` invokes `client-chatbot` with the authenticated Supabase Flutter client and returns `reply`.

- [ ] Create the immutable view message model with no persistence serialization or database ID.
- [ ] Implement `reply` using `SupabaseClientProvider.client.functions.invoke('client-chatbot', body: ...)`, mapping prior assistant messages to Gemini role `model` and client messages to `user`.
- [ ] Parse only the documented `{reply}` response; convert `FunctionException` and malformed responses to friendly exceptions while preserving retryability where available. Never add any API key to this Dart repository.

### Task 3: Add the client chat screen and dashboard entry point

**Files:**
- Create: `lib/presentation/client_dashboard_screen/client_chat_screen.dart`
- Modify: `lib/routes/app_routes.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_dashboard_screen.dart`

**Interfaces:**
- Add `AppRoutes.clientChat = '/client-chat-screen'`.
- Add `ClientChatScreen` as a client-only route; its state owns the in-memory message list and `ClientChatbotRepository` instance.

- [ ] Build a focused screen with message bubbles, a multiline composer, send action, typing/loading indicator, retryable error state, and starter prompts for services, payment rules, and “What’s my next booking?”.
- [ ] On send, add the user message in memory, call the repository with up to the last 8 prior messages, then add the assistant response. Prevent overlapping sends and retain the failed user draft for retry.
- [ ] Clear chat state when the route is disposed; do not write transcript messages to Supabase/local storage or log their text.
- [ ] Add the chat route to the client allowlist and leave staff role routing unchanged.
- [ ] Add a compact floating chat action above the existing “Book Now” action using a `Column(mainAxisSize: MainAxisSize.min)` so narrow screens do not get an over-wide pair of FABs. Route it to `AppRoutes.clientChat`.

### Task 4: Prepare deployment and handoff

**Files:**
- No additional files; use the function, configuration, and Flutter changes above.

- [ ] Confirm `GEMINI_API_KEY` is already present in Supabase Edge Function Secrets; do not ask the user to paste or re-enter its value.
- [ ] Prepare the command `npx --yes supabase functions deploy client-chatbot` for the user. Do not deploy the remote function until the user explicitly authorizes deployment after reviewing the completed local code.
- [ ] Give the user the required Flutter launch command using `.env.supabase.json` and the deployment step, and state clearly that client-facing chatbot calls will only work after the function is deployed.
- [ ] Do not claim the chatbot is live until deployment is authorized and its deployed status is confirmed.

## Official API references

- Supabase authenticated Edge Function pattern and RLS-scoped `ctx.supabase`: [Securing Edge Functions](https://supabase.com/docs/guides/functions/auth).
- Gemini REST request and API-key header: [Gemini API generateContent](https://ai.google.dev/gemini-api/docs/generate-content).
