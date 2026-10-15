# Real-Time Booking Notifications Implementation Plan

> **Implementation status:** Complete in the current workspace. The hosted Supabase migration still needs to be applied by the project owner.

**Goal:** Notify clients and the admin of online booking events in real time, show unread booking badges, and keep staff action counts distinct from unread notifications.

**Architecture:** Reuse `public.notifications`, its owner-based RLS, and the existing Supabase Realtime publication. A database trigger creates the missing booking and lifecycle notices in the same transaction as each booking event. Flutter generalizes notification state to the signed-in user, adds client and admin badges, and refreshes booking hydration when payment submissions or transactions change so staff task counts remain live.

**Tech Stack:** Flutter/Dart, Supabase Postgres, Supabase Realtime, SQL migrations.

**Spec:** `docs/superpowers/specs/2026-10-16-realtime-booking-notifications-design.md`

## Global Constraints

- Preserve existing notification RLS: a user can read and mark read only their own rows.
- Keep unread-notification counts separate from counts of bookings needing staff action.
- Do not duplicate existing payment-verified, payment-rejected, confirmed, cancelled-client, or balance-collected client notices.
- Do not add push notifications, walk-in notifications, or a separate notification service.
- Database notification writes must be idempotent using the existing unique `(user_id, event_key)` constraint.
- Do not add or run automated tests for this task unless the user asks for testing or verification.

## Review Focus

- Multiple admin profiles receive their own new-booking notification, without exposing it to cashier or client profiles.
- Realtime changes to payment submissions and payment transactions refresh the derived staff action counts even when `bookings.updated_at` does not change.
- Reopening a dashboard does not reset persisted unread state; entering the bookings view marks only the signed-in user's booking-linked notices read.
- Existing confirmation, cancellation, payment, and balance notices are not duplicated by the new event trigger.
- A Realtime failure retains the last loaded bookings and notifications rather than displaying false zero counts.

---

### Task 1: Add transaction-safe database notifications

**Files:**
- Create: `supabase/migrations/202610160001_realtime_booking_notifications.sql`

**Interfaces:**
- Produces the notification rows consumed by the existing `PaymentBookingStore` stream and `public.notifications` RLS policies.
- Uses the existing notification event fields `user_id`, `booking_id`, `event_key`, `title`, and `message`.

- [x] Add a `SECURITY DEFINER` trigger function with a fixed `search_path` that inserts `new_booking:<booking-id>` notifications for admin profiles after a booking is inserted.
- [x] Extend that function for booking status updates: notify the client on `checkedIn`, `inProgress`, and `completed`; notify admins on a client-initiated cancellation only.
- [x] Leave existing SQL notification paths in place for payment verification/rejection, confirmation/staff cancellation, and balance collection; use distinct event keys only for the new events.
- [x] Add triggers for booking insertion and status changes. Protect inserts with `ON CONFLICT (user_id, event_key) DO NOTHING`.
- [x] Confirm the migration needs no publication change because the existing report migration already publishes `notifications`, `payment_submissions`, and `payment_transactions`.

### Task 2: Generalize live notification and booking state

**Files:**
- Modify: `lib/data/payment_booking_store.dart`
- Modify: `lib/data/repositories/booking_repository.dart`
- Modify: `lib/data/repositories/supabase_booking_repository.dart`

**Interfaces:**
- Expose `noticesForUser(String userId)`, `unreadNoticeCountForUser(String userId)`, and `unreadBookingNoticeCountForUser(String userId)` from `PaymentBookingStore`.
- Change the notice model owner field to `userId`; keep distinct `title`, `message`, `createdAt`, `bookingId`, and `isRead` fields.
- Provide `markNoticeRead(String noticeId, {required String userId})` and `markBookingNoticesRead({required String userId})`.
- Add `watchPaymentSubmissions()` and `watchPaymentTransactions()` to `BookingRepository`, each returning `Stream<List<Map<String, dynamic>>>` under the current user's RLS-visible rows.

- [x] Represent all new event keys (`new_booking`, `client_cancelled`, `booking_checked_in`, `booking_service_started`, `booking_service_completed`) without mapping them to the default confirmed type.
- [x] Change notification ownership in the Dart model from client-only naming to user/owner naming, adjusting existing client readers without changing client behavior.
- [x] Track `payment_submissions` and `payment_transactions` Realtime changes for the authenticated user's RLS-visible rows; debounce refreshes and re-hydrate bookings so pending-review and balance-due counts update even when the booking row did not change.
- [x] Implement `markBookingNoticesRead` using the existing owner-protected read RPC per unread booking notice; update local read state only after successful writes and preserve errors for retry.
- [x] Ensure `clearSession()` cancels the new subscriptions and clears their references.

### Task 3: Add client booking-tab unread badge

**Files:**
- Modify: `lib/widget/app_navigation.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_notifications_screen.dart`

**Interfaces:**
- Read live notification counts from `PaymentBookingStore` and owner identity from the authenticated session.

- [x] Wrap navigation destinations in a store-driven builder so **Bookings** shows a numeric badge for unread booking-linked notices only.
- [x] When the user selects **Bookings**, mark that user's booking-linked notifications read and navigate to the booking branch.
- [x] Apply the same mark-read behavior when the notifications page's **View bookings** action opens the bookings branch.
- [x] Keep the existing client bell and notifications page behavior, apart from owner-generic notices and the expanded notice types.

### Task 4: Add admin notifications and staff action badges

**Files:**
- Modify: `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart`

**Interfaces:**
- Use `PaymentBookingStore` live notices and bookings; continue using current `_AdminSection` navigation and sections.

- [x] Replace the no-op bell with a real-time unread count and a recent-notifications dialog.
- [x] In the dialog, show the notice title/message/time; selecting a booking notice marks it read and opens **Bookings**.
- [x] Add the unread booking-notification count to the **Bookings** sidebar entry and mark the current admin's booking notices read when that section is opened.
- [x] Add a distinct **Payment Verification** action count derived from `pendingBookings`.
- [x] Add a distinct **Checkout** action count derived from verified online bookings in `checkedIn`, `inProgress`, or `completed` with positive `remainingBalance`.
- [x] Keep notification badges and action counts visually distinguishable and update them from the existing store notifier.

### Task 5: Document hosted migration and user acceptance flow

**Files:**
- Modify: `docs/superpowers/specs/2026-10-16-realtime-booking-notifications-design.md` only if implementation reveals a necessary design adjustment.

**Interfaces:**
- Deployment command remains `npx --yes supabase db push` from the project folder.

- [x] Provide the user with the migration command and the Flutter rerun command after implementation.
- [x] Describe a manual acceptance sequence: client books; admin sees bell/Bookings; admin verifies or rejects payment; client sees update; staff checks in and advances service; client sees each stage; staff collects balance; Checkout task count clears and client receives the balance notice.
- [x] Do not apply a remote database migration or deploy/publish the application from the implementation session.
