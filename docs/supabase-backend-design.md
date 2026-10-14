# Supabase Backend Design

## Status

Design specification for the E-Relax Flutter app. This document does not apply
changes to the Supabase project. Implementation begins only after this spec and
the subsequent implementation plan are approved.

## Goal

Persist the app's operational data in Supabase so the client, admin, cashier,
and therapist views use the same records across devices. Preserve the current
UI and workflows where practical while moving data access out of in-memory
lists and into a secured backend.

## Current project findings

- `supabase_flutter` is declared in `pubspec.yaml`, but `main.dart` does not
  initialize Supabase.
- Sign-up and sign-in are prototype routing based on text in the email address;
  they do not authenticate users.
- Bookings, payment notices, payment history, and booking activity live in the
  singleton `PaymentBookingStore` and disappear when the process restarts.
- Therapist records and duty schedules live in `TherapistRosterStore` memory;
  selected therapist photos are byte arrays in that memory.
- Walk-ins and walk-in sale records are lists owned by the admin dashboard
  screen. Online booking transactions are derived from in-memory bookings.
- Services are a compile-time catalog. Sales and service reports aggregate
  those local records; PDF files are generated on demand.
- There is no Supabase MCP connection available in the current agent session.
  The project URL and publishable key do not grant schema-management access.

## Recommended architecture

Use Supabase Auth, Postgres, Storage, and Realtime behind repositories. Keep
the current `ChangeNotifier` stores as view-state adapters initially, but have
them load and mutate data through repository interfaces instead of being the
source of truth. This limits UI changes and provides a single boundary for
loading, errors, authorization, and database operations.

Initialize `supabase_flutter` in `main.dart` using build-time configuration
(for example, `--dart-define-from-file`). Only the project URL and publishable
key belong in the Flutter app. Never ship a Supabase secret or service-role key
in the client.

The first release assumes network access for writes. Show clear loading,
success, and failure states; do not silently claim that an unsaved action
succeeded. Full offline queueing and conflict resolution are out of scope.

## Identity and roles

- Use Supabase Auth identities and a `profiles` row keyed to `auth.users.id`.
- Store explicit roles: `client`, `admin`, `cashier`, and `therapist`.
- Clients self-register as clients. Staff roles must be assigned through a
  trusted admin provisioning flow; users cannot promote themselves.
- Replace email-substring routing with role-aware session loading and guarded
  navigation. Sign-out clears the Supabase session and local view state.
- Therapist email and phone remain optional profile fields. A therapist with
  no linked auth account can still be scheduled and selected for bookings, but
  cannot sign in to the therapist dashboard until an account is linked.

## Data model

Use UUID primary keys for new records unless a stable existing service ID must
be retained. Store timestamps as `timestamptz`, money as integer minor units or
`numeric(12,2)` consistently (recommend `numeric(12,2)` because existing
prices are whole PHP pesos), and reference records through foreign keys.

| Entity | Purpose and main relationships |
| --- | --- |
| `profiles` | Auth user ID, role, display name, contact fields, created/updated timestamps. |
| `services` | Persisted service name, description, price, duration, image metadata, active flag, and display order. Seed from the current service catalog. |
| `therapists` | Name, optional email/phone, optional linked auth profile, specialty service, profile-image storage path, active flag. |
| `therapist_duty` | Therapist and work date, with unique `(therapist_id, work_date)` assignment. |
| `bookings` | Client, service, therapist, appointment date/time, duration, price/discount snapshot, booking status, check-in/service timestamps, cancellation details, and created/updated timestamps. |
| `payment_submissions` | Versioned proof submissions linked to a booking: amount, transaction reference, private storage path, status, submit/review timestamps, reviewer, and rejection reason. A resubmission inserts a new row; it does not erase prior proofs. |
| `payment_transactions` | Immutable ledger entries for verified online down payments, online balance payments, and walk-in checkout payments; includes method, amount, actor, timestamp, source reference, and unique idempotency key. |
| `walk_ins` | Client/contact snapshot, service/therapist references, price/duration snapshot, service start and completion timestamps, lifecycle status, and timestamps. |
| `booking_activity` | Append-only audit events for booking and payment state changes, including actor, event, timestamp, and optional note. |
| `notifications` | User-owned notices linked to a booking/payment, message/type, created time, and read time. |

No separate report tables are required initially. Reports are aggregates over
the persisted transaction ledger and completed service records. Receipts are
regenerated from canonical booking and payment records; the receipt PDF itself
does not need to be stored unless later required.

## Storage

- Put payment proof screenshots in a private `payment-proofs` bucket.
- Put therapist photos in a therapist-profile bucket with policies that permit
  client display and staff management.
- Save object paths in database rows, not image bytes. Use authorized access or
  short-lived signed URLs for private objects.
- If an upload succeeds but its database transaction fails, remove the
  unreferenced object where practical; surface upload errors to the user.

## Authorization and database policies

Enable RLS on every exposed application table and grant only the operations
needed by each role. Policies must use the authenticated user ID and trusted
role/profile records.

- Clients can read their own profile, bookings, proofs, payment history,
  receipts derived from their bookings, and notifications. They can create
  bookings/proof submissions only for themselves and cannot set verified or
  confirmed statuses.
- Admins can manage services, therapist profiles, and duty schedules; review
  all clinic bookings and proofs; and perform authorized operational actions.
- Cashiers can manage walk-ins, checkout transactions, and balance collection
  as allowed by the role design. They should not gain admin account-management
  privileges.
- Therapists can read their own profile and assigned bookings, and perform
  only the allowed service lifecycle actions.
- Proof storage policies must match booking ownership for clients and staff
  review permissions. Never make payment proof files public.
- Report queries must be restricted to authorized staff and respect RLS; avoid
  an unscoped view that bypasses the intended row policies.

Use database RPCs/transactions for multi-record financial and lifecycle
operations. Clients must not directly write privileged status columns. Keep
manual tool approval enabled when using an MCP connection.

## Atomic business workflows

1. **Online booking submission:** verify the chosen therapist is on duty and the
   time slot is still free; save a pending booking and initial proof submission.
   Prevent overlapping bookings server-side so two devices cannot reserve the
   same therapist concurrently.
2. **Verify payment:** require a pending submission with a non-empty reference,
   accessible proof, and the expected 30% amount; atomically mark it verified,
   confirm the booking, append activity, insert one down-payment ledger row,
   and create one client notification. Use an idempotency key so retries cannot
   duplicate confirmation, revenue, or notification.
3. **Reject payment:** require a reason; atomically mark that submission
   rejected, preserve the booking as unconfirmed, append activity, and notify
   the client. Resubmission creates a new pending proof version and retains the
   rejection history.
4. **Appointment lifecycle:** authorized staff/therapist actions update
   check-in, in-progress, and completion timestamps and append activity. Timer
   displays derive from these saved timestamps, including the selected
   five-minute preparation allowance.
5. **Online balance collection:** after service completion, collect exactly the
   remaining amount, record payment method/actor/time, append a ledger entry,
   and notify the client atomically.
6. **Walk-in:** create an unpaid visit first; persist its service start and
   five-minute preparation allowance; allow checkout when requested (consistent
   with the agreed flow); then atomically save payment and ledger records.
7. **Cancellation:** require a reason and record the acting staff member and
   timestamp. Do not delete financial or booking history.

## Sales and service reports

- **Sales report:** sum captured ledger events in the selected daily, weekly,
  monthly, yearly, or custom date range. Count a 30% online down payment once
  after verification, the online balance when collected, and a walk-in sale
  when checkout payment is collected. This preserves the agreed treatment of
  verified down payments in gross sales while avoiding counting unpaid booking
  value as cash received.
- **Service report:** count services when completed, grouped by current service
  identity and date of completion; include completed online appointments and
  completed walk-ins. Keep the existing per-service chart colors and PDF
  download behavior.
- Keep report range and chart presentation in the client; fetch report rows or
  aggregates from saved records. PDF export remains on demand.
- **Open business definition:** the current walk-in screen infers completion
  from elapsed timer duration and has no explicit persisted completion action.
  The implementation plan must state whether walk-in completion is recorded
  explicitly by staff or derived from `started_at + preparation + service
  duration`. The report must never count a newly started walk-in as completed.

## Realtime and refresh

Subscribe to authorized booking, payment, therapist-duty, and notification
changes so separate devices refresh promptly. Realtime events are hints to
reload authorized records; the database remains the source of truth. Keep a
manual refresh/reload fallback and handle reconnects. Realtime subscriptions
must not expose records beyond RLS.

## Migration and delivery sequence

1. Add migrations and a development-safe schema, policies, Storage buckets, and
   seed data for services.
2. Connect Supabase Auth and role/profile handling; guard all routes.
3. Introduce repositories and migrate therapist/service data.
4. Migrate booking creation, proof upload/review/resubmission, booking activity,
   and client notifications.
5. Migrate therapist scheduling, service timers, and walk-ins.
6. Add atomic sales/balance ledger operations and connect sales/service
   reports.
7. Add Realtime subscriptions, verify role boundaries and core workflows on
   two devices, then deploy.

Existing in-memory prototype records are not recoverable after process exit and
will not migrate automatically. Any real records already collected outside
Supabase require a deliberate import. The planned Gemini chatbot is a later
phase; do not put its API key in Flutter. If conversation history is wanted,
design that storage and retention separately.

## Acceptance criteria

- Client, admin, cashier, and therapist sessions persist securely across app
  restarts and enforce their roles.
- A booking created on one device appears on the authorized views of other
  devices and remains after restart.
- Proof files are private; payment status and booking confirmation cannot be
  set directly by a client.
- Verification, rejection, resubmission, balance collection, and checkout each
  produce one consistent set of status, audit, notification, and ledger rows,
  including on retry.
- Therapists, optional profile/contact fields, photos, and daily schedules are
  saved and reflected in booking availability.
- Reports derive from saved events with the agreed date and completion rules;
  downloadable PDFs match the displayed totals.
- Unauthorized users cannot read or mutate another client's booking, proof, or
  notification data.
