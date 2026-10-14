# E-Relax Client Chatbot Design

## Status

Design specification only. No chatbot implementation or Supabase function has
been deployed. Implementation starts after this specification and its
implementation plan are reviewed and approved.

## Goal

Give signed-in clients a conversational way to get accurate clinic information
and answers about their own bookings from the E-Relax client dashboard.

## Approved scope

- A floating chat button on the client dashboard opens a dedicated chat view.
- The assistant answers clinic questions using the live service catalog and a
  maintained set of clinic facts and policies.
- A signed-in client can ask about their own bookings. Responses may summarize
  service, appointment date/time, therapist, booking status, and payment
  summary where the signed-in user has access to that information.
- Chat messages and recent conversation context are kept in the current view
  only; no separate chat-history table or long-term transcript storage is
  introduced.
- The assistant does not create, edit, cancel, or reschedule bookings.
- The assistant does not provide medical diagnoses or treatment advice. If it
  lacks a reliable answer, it says so and directs the client to contact the
  clinic.

## Current project findings

- Supabase Flutter is already declared as an app dependency.
- `ClientDashboardScreen` already has a floating “Book Now” action; the chat
  entry point should coexist with it without obscuring it on narrow screens.
- `supabase/functions/client-chatbot/index.ts` is the generated Supabase
  “Hello” sample and has not been replaced or deployed.
- The Gemini API key is stored in Supabase Edge Function secrets as
  `GEMINI_API_KEY` and must remain server-side.
- The booking table contains client ownership, service/therapist snapshots,
  appointment date/time, amount, and lifecycle status. Existing RLS limits a
  client to reading their own bookings and associated payment records.
- Services are stored in `public.services`; inactive services must not be
  advertised as bookable.

## Architecture and request flow

1. The signed-in client opens the chat from the client dashboard and submits a
   message.
2. Flutter invokes the `client-chatbot` Supabase Edge Function using the
   current authenticated Supabase session. The Flutter app contains only the
   Supabase URL and publishable key; it never contains a Gemini API key.
3. The Edge Function rejects unauthenticated requests, validates message size
   and request shape, and uses the caller's authorization context to load only
   the caller's permitted booking/payment summaries and active clinic services.
   It must not use a service-role client to fetch client data.
4. The function sends the user's message and the minimum relevant, authorized
   context to Gemini using `GEMINI_API_KEY` from function secrets. The prompt
   treats user text as untrusted and instructs the model to answer only from
   supplied clinic facts and booking context.
5. Flutter sends the current question with bounded recent turns from the
   current in-memory conversation. The function returns a bounded plain-text
   response, which Flutter displays while preserving the draft on retryable
   errors.

The model is not allowed to execute database queries or actions. Booking data
is fetched and authorization-filtered by the Edge Function before the Gemini
request; the model only phrases that data into an answer.

## User experience

- Use a floating chat entry point on the dashboard, positioned so it does not
  collide with “Book Now” at mobile widths.
- Provide a focused chat screen with message bubbles, a text composer, send
  action, loading state, and retry/error state.
- Show a few starter prompts, including a clinic-services question and “What’s
  my next booking?”.
- Keep displayed booking/payment details concise and clearly tie them to the
  current client's own records.
- Keep only bounded recent turns in view state so follow-up questions make
  sense; do not store transcript history after the chat view is closed.

## Security and privacy

- Require an authenticated client JWT. Reject missing, expired, or invalid
  sessions before reading data or calling Gemini.
- Apply user-scoped RLS for booking, payment, and service reads; do not trust a
  client-supplied user ID or booking ID as proof of access.
- Keep Gemini credentials only in Supabase Edge Function secrets. Never expose
  the secret in Flutter, `.env.supabase.json`, browser logs, or responses.
- Send Gemini only the information needed for the current question; never send
  payment proof files, passwords, auth tokens, or other clients' information.
- Limit input length and response size, handle upstream rate limits, and avoid
  logging message content or private booking details.

## Failure behavior

- Missing login: ask the client to sign in again; do not issue a Gemini request.
- Database/network/Gemini failure: show a plain retry message and keep the
  user's unsent text available.
- Missing/ambiguous data: say the answer is unavailable and give a clinic
  contact route rather than guessing.
- Booking question with no records: say no bookings were found for the signed-in
  account and offer a path to book.

## Out of scope for the first version

- Creating, editing, cancelling, or rescheduling bookings.
- Human live-agent chat or admin chat transcripts.
- Persistent transcript storage, chat analytics, and attachments/voice input.
- Medical advice, diagnosis, or personalized treatment recommendations.
- Unauthenticated/general public chatbot access.

## Acceptance criteria

1. A client can open the chat from the client dashboard on mobile and web without
   obscuring the existing booking action.
2. The chat answers active service catalog and configured clinic-policy
   questions using the current data, not hard-coded examples that drift.
3. A signed-in client can get accurate summaries for their own booking and
   payment state; another client's records cannot be obtained by changing
   request fields or prompt text.
4. The endpoint rejects unauthenticated requests and malformed/oversized
   messages without exposing secrets or private data.
5. Gemini/network errors and unavailable answers produce understandable,
   retryable or clinic-contact guidance rather than fabricated answers.
6. Chat messages are not retained in a server-side conversation history.

## Verification plan

- Review function authorization and data queries against the existing RLS
  policies before deployment.
- Exercise clinic FAQ, own-booking lookup, no-booking, sign-out/expired session,
  malformed input, and Gemini/network failure cases.
- Confirm deployed function secrets are read server-side and are absent from
  Flutter assets, build defines, logs, and responses.
- Verify the chat entry point and chat screen on a narrow mobile layout and
  Chrome.
