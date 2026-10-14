# Supabase Backend Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist E-Relax accounts, therapists, bookings, payments, walk-ins, sales, history, notifications, and report inputs in Supabase so authorized devices share one source of truth.

**Architecture:** Initialize `supabase_flutter`, then replace local singleton/list ownership with focused repositories that feed the existing notifier-based UI. Use Postgres RLS for row access, database RPCs for atomic/idempotent business operations, Storage for images, and Realtime events to trigger authorized reloads.

**Tech Stack:** Flutter/Dart, `supabase_flutter`, Supabase Auth, Postgres SQL migrations, Supabase Storage, Supabase Realtime, existing PDF services.

**Spec:** `docs/supabase-backend-design.md`

## Global Constraints

- Use only the project URL and publishable key in Flutter; never put secret or service-role keys in the app.
- Enable RLS on every exposed application table and grant only role-required operations.
- Keep payment proof screenshots private and store object paths rather than image bytes in database rows.
- Do not allow client-written payment verification or confirmed booking statuses.
- Verify therapists' duty and overlapping appointment times on the server before accepting bookings.
- Count online 30% down payments after verification, balances on collection, and walk-in sales on checkout.
- Include completed online bookings and completed walk-ins in the service report, grouped by completion date and service.
- Keep the five-minute preparation allowance and allow walk-in checkout whenever requested.
- Assume online access for writes; show loading and failure states without reporting unsaved changes as successful.
- Preserve the existing UI and PDF report/receipt behavior unless a backend requirement needs a focused adjustment.
- Do not add or run tests unless the user explicitly requests testing or verification.

## Review Focus

1. Concurrent booking attempts for the same therapist and overlapping interval must not both succeed; enforce within one database transaction.
2. Repeated verification, rejection, or checkout requests must not duplicate ledger entries, notifications, or state transitions; use unique idempotency keys and state checks.
3. A client attempting to update another client's records or privileged status fields must be denied by RLS/database functions.
4. Failed or interrupted proof/photo uploads must not appear as valid payment evidence and must surface a retryable error.
5. Expired sessions, network loss, or Realtime disconnection must not display stale actions as saved; re-fetch authorized state and show the operation result.

---

### Task 1: Add the database migration foundation

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/202610130001_profiles_services_therapists.sql`
- Create: `supabase/README.md`

**Interfaces:**
- Produces tables and policies consumed by later tasks: `profiles`, `services`, `therapists`, and `therapist_duty`.
- Profile role values are exactly `client`, `admin`, `cashier`, and `therapist`.
- Therapist `email`, `phone`, and profile-image path are nullable; therapist duty has a unique `(therapist_id, work_date)` pair.

- [ ] Define enums/check constraints, foreign keys, timestamp and money types, indexes, RLS, grants, and role policies for the four tables.
- [ ] Seed the persisted service catalog from `lib/data/service_catalog.dart` using stable IDs and preserve the current names, prices, and durations.
- [ ] Keep admin role assignment out of client self-registration; document initial trusted admin provisioning through Supabase Dashboard/SQL Editor.
- [ ] Document local migration application and required Data API exposure. No remote migration is applied by this file task.

### Task 2: Connect app configuration and Supabase Auth

**Files:**
- Create: `lib/models/profile.dart`
- Create: `lib/data/backend/supabase_client_provider.dart`
- Create: `lib/data/repositories/auth_repository.dart`
- Create: `lib/data/repositories/supabase_auth_repository.dart`
- Create: `lib/data/stores/auth_session_store.dart`
- Modify: `lib/main.dart`
- Modify: `lib/routes/app_routes.dart`
- Modify: `lib/presentation/sign_up_login_screen/sign_up_login_screen.dart`
- Modify: `lib/presentation/sign_up_login_screen/widget/auth_form_widget.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_profile_screen.dart`
- Modify: `lib/presentation/client_dashboard_screen/widget/dashboard_header_widget.dart`

**Interfaces:**
- `AuthRepository.signIn({required String email, required String password}) -> Future<Profile>`
- `AuthRepository.signUpClient({required String email, required String password, required String displayName}) -> Future<void>`
- `AuthRepository.signOut() -> Future<void>`
- `AuthSessionStore` exposes the current authenticated profile and a `Listenable` refresh source for GoRouter.

- [ ] Initialize Supabase before `runApp` from build-time URL and publishable-key configuration; fail clearly when either is missing.
- [ ] Replace email-substring routing and delayed fake login with Supabase Auth and role-loaded profiles.
- [ ] Add guarded redirects for client, admin, cashier, and therapist sections; preserve existing route destinations and admin/cashier UI structure.
- [ ] Keep self-registration restricted to clients; ensure password reset uses Supabase Auth rather than a success-only placeholder.
- [ ] Persist display-name/profile edits through the repository and clear session-derived client state on sign-out.
- [ ] Provide setup instructions using `--dart-define-from-file` and a non-secret example config; do not place the provided real key in committed files.

### Task 3: Persist services, therapist profiles, and duty rosters

**Files:**
- Create: `lib/models/service.dart`
- Create: `lib/models/therapist_profile.dart`
- Create: `lib/data/repositories/clinic_repository.dart`
- Create: `lib/data/repositories/supabase_clinic_repository.dart`
- Modify: `lib/data/therapist_roster_store.dart`
- Modify: `lib/data/service_catalog.dart`
- Modify: `lib/presentation/admin_dashboard_screen/therapist_management_screen.dart`
- Modify: `lib/presentation/client_dashboard_screen/widget/therapist_avatar_row_widget.dart`
- Modify: `lib/presentation/Appointment_booking/widget/therapist_selector_widget.dart`

**Interfaces:**
- `ClinicRepository.watchServices() -> Stream<List<Service>>`
- `ClinicRepository.watchTherapists() -> Stream<List<TherapistProfile>>`
- `ClinicRepository.watchDutyForDate(DateTime date) -> Stream<List<TherapistProfile>>`
- `ClinicRepository.saveTherapist(TherapistProfile profile, Uint8List? photo) -> Future<TherapistProfile>`
- `ClinicRepository.saveDuty(DateTime date, Set<String> therapistIds) -> Future<void>`
- `ClinicRepository.availableTherapists({required DateTime date, required String startTime, required int durationMinutes}) -> Future<List<TherapistProfile>>`

- [ ] Convert service reads to database-backed records while preserving stable service IDs, prices, durations, order, and existing UI presentation.
- [ ] Persist optional therapist email/contact and upload optional profile photos to Storage; store only their object path in Postgres.
- [ ] Persist daily duty selections and query available therapists for online booking and walk-ins.
- [ ] Keep therapist photos optional and retain initials placeholders when no image is stored.
- [ ] Remove the in-memory roster as a source of truth only after its existing consumers use `ClinicRepository`.

### Task 4: Persist bookings, payment proofs, notifications, and audit history

**Files:**
- Create: `supabase/migrations/202610130002_bookings_payments_notifications.sql`
- Create: `lib/models/create_booking_request.dart`
- Create: `lib/models/payment_submission.dart`
- Create: `lib/data/repositories/booking_repository.dart`
- Create: `lib/data/repositories/supabase_booking_repository.dart`
- Modify: `lib/models/booking.dart`
- Modify: `lib/data/payment_booking_store.dart`
- Modify: `lib/presentation/Appointment_booking/appointment_booking_screen.dart`
- Modify: `lib/presentation/Appointment_booking/widget/payment_step_widget.dart`
- Modify: `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart`
- Modify: `lib/presentation/admin_dashboard_screen/online_booking_in_progress_screen.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_bookings_screen.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_notifications_screen.dart`
- Modify: `lib/presentation/client_dashboard_screen/widget/upcoming_booking_widget.dart`
- Modify: `lib/services/booking_receipt_service.dart`

**Interfaces:**
- `BookingRepository.watchForClient() -> Stream<List<Booking>>`
- `BookingRepository.watchForStaff() -> Stream<List<Booking>>`
- `BookingRepository.createOnlineBooking(CreateBookingRequest request, Uint8List proof) -> Future<Booking>`
- `BookingRepository.verifyPayment(String submissionId) -> Future<void>`
- `BookingRepository.rejectPayment(String submissionId, {required String reason}) -> Future<void>`
- `BookingRepository.resubmitProof(String bookingId, {required String reference, required Uint8List proof}) -> Future<void>`
- `BookingRepository.transition(String bookingId, BookingStatus next, {String? reason}) -> Future<void>`
- `BookingRepository.markNotificationRead(String notificationId) -> Future<void>`

- [ ] Add booking, payment-submission, booking-activity, and notification tables with ownership-based RLS and private proof-bucket policies.
- [ ] Implement the booking creation RPC with a server-side duty/overlap check and atomic booking plus initial submission creation.
- [ ] Upload proof bytes to Storage, pass only the private object path to the database, and report failed uploads/submissions without a false success state.
- [ ] Implement idempotent verify/reject/resubmit RPCs. Verification confirms the booking, appends activity, creates a single payment-ledger entry, and emits one notification in the same transaction.
- [ ] Preserve prior proof submissions and rejection reasons; clients can create a replacement only after rejection and cannot write review/status fields.
- [ ] Persist check-in, in-progress, completion, cancellation, reviewer and actor timestamps. Enforce reason-required cancellation and append-only activity history.
- [ ] Load client booking/payment history from owned rows and regenerate downloadable receipts from canonical database values.
- [ ] Replace local `PaymentBookingStore` ownership with repository-backed state and remove the demo admin actor ID.

### Task 5: Persist walk-ins, checkout, and the payment ledger

**Files:**
- Create: `supabase/migrations/202610130003_walkins_sales_ledger.sql`
- Create: `lib/models/walk_in.dart`
- Create: `lib/models/payment_transaction.dart`
- Create: `lib/data/repositories/cashier_repository.dart`
- Create: `lib/data/repositories/supabase_cashier_repository.dart`
- Modify: `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart`

**Interfaces:**
- `CashierRepository.watchWalkIns() -> Stream<List<WalkIn>>`
- `CashierRepository.startWalkIn(CreateWalkInRequest request) -> Future<WalkIn>`
- `CashierRepository.checkoutWalkIn(String walkInId, {required String method}) -> Future<void>`
- `CashierRepository.collectOnlineBalance(String bookingId, {required String method}) -> Future<void>`
- `CashierRepository.watchPaymentTransactions(DateTimeRange range) -> Stream<List<PaymentTransaction>>`

- [ ] Add durable walk-in records and an append-only payment transaction ledger with unique idempotency keys and role-specific RLS.
- [ ] Persist service start time and service duration; derive walk-in completion at `started_at + 5 minutes + duration` so countdowns survive restart and sync across devices.
- [ ] Keep checkout available whenever requested. Checkout records the selected method and payment amount atomically, including if the timer has not reached completion.
- [ ] Collect the online balance only after service completion, for exactly the remaining amount, and record the cashier and timestamp.
- [ ] Insert walk-in revenue at checkout, online down-payment revenue once when verified, and online balance revenue once when collected.
- [ ] Replace `_walkIns` and `_sales` widget-owned lists with repository records; preserve existing cashier screen layout and status labels.

### Task 6: Connect sales and service reports to saved records

**Files:**
- Create: `lib/data/repositories/report_repository.dart`
- Create: `lib/data/repositories/supabase_report_repository.dart`
- Create: `lib/models/report_data.dart`
- Create: `supabase/migrations/202610130004_report_queries.sql`
- Modify: `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart`
- Modify: `lib/services/report_pdf_service.dart`

**Interfaces:**
- `ReportRepository.loadSales(DateTimeRange range, SalesBucketSize bucketSize) -> Future<SalesReportData>`
- `ReportRepository.loadServices(DateTimeRange range, SalesBucketSize bucketSize) -> Future<ServiceReportData>`
- Report rows carry bucket labels, total counts/amounts, per-service counts, and transaction counts; the client keeps current chart colors and date-range controls.

- [ ] Aggregate authorized payment-ledger rows for daily, weekly, monthly, yearly, and custom sales reports.
- [ ] Aggregate completed online bookings and timer-completed walk-ins by service and completion date.
- [ ] Apply staff-only RLS/role checks to report queries and return only the selected date range.
- [ ] Keep both PDF downloads based on the same report data currently shown onscreen so exported totals and chart values match.
- [ ] Remove all report calculations over local `_sales`, `_walkIns`, and in-memory bookings.

### Task 7: Add authorized Realtime refresh and error handling

**Files:**
- Create: `lib/data/repositories/realtime_subscription_manager.dart`
- Modify: `lib/data/stores/auth_session_store.dart`
- Modify: `lib/data/therapist_roster_store.dart`
- Modify: `lib/data/payment_booking_store.dart`
- Modify: `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_dashboard_screen.dart`
- Modify: `lib/presentation/client_dashboard_screen/client_bookings_screen.dart`
- Modify: `lib/presentation/therapist_dashboard_screen/therapist_dashboard_screen.dart`

**Interfaces:**
- `RealtimeSubscriptionManager.startForCurrentProfile(Profile profile) -> void`
- `RealtimeSubscriptionManager.dispose() -> Future<void>`
- Realtime callbacks invalidate and reload repository state; they do not authorize or directly apply status transitions.

- [ ] Enable only the required Realtime tables and verify subscriptions respect database RLS.
- [ ] Start subscriptions after auth/profile load and dispose/restart them on logout, role change, or reconnect.
- [ ] Make manual refresh trigger repository reloads instead of only rebuilding the current widget.
- [ ] Surface loading, upload, permission, expired-session, and network errors without optimistic success; allow retry where safe.

### Task 8: Document setup, migration, and release handoff

**Files:**
- Modify: `supabase/README.md`
- Create: `.env.supabase.example`
- Modify: `.gitignore`

- [ ] Document required project settings, migration application, initial admin provisioning, Storage policies, Data API exposure, and optional Realtime publication setup.
- [ ] Document separate development and production Supabase projects and state that prototype in-memory records cannot be recovered automatically.
- [ ] Ensure real keys, access tokens, and local environment files are excluded from version control.
- [ ] Provide a manual two-device acceptance walkthrough for account roles, booking/payment flows, therapist roster, cashier sales, and reports; do not claim production readiness until the user runs it against their project.

## Plan self-review

- **Spec coverage:** Identity/roles: Task 2; services/therapists/duty: Tasks 1 and 3; bookings/payments/proofs/notifications/audit/receipts: Task 4; walk-ins/balance/sales ledger: Task 5; reports/PDFs: Task 6; Realtime/refresh: Task 7; setup/security/migration/release handoff: Tasks 1, 2, and 8; future Gemini work remains excluded by the spec.
- **Cross-task types:** `Profile`, `Service`, `Booking`, `BookingStatus`, `CreateBookingRequest`, `TherapistProfile`, `WalkIn`, `PaymentTransaction`, `SalesBucketSize`, `SalesReportData`, and `ServiceReportData` must be defined in their stated model/repository tasks before consumers use them. The exact model fields are taken from the spec entities and existing `Booking` fields.
- **Scope:** Tasks are ordered by dependency: schema/auth, catalog/staff, bookings/payments, cashier ledger, reports, then subscriptions and handoff. Each phase leaves the app with one more persisted workflow. No Supabase cloud changes occur until migration application is explicitly authorized and a writable connection or user-run SQL is available.
- **Verification constraint:** Per the active instruction, this plan does not include adding or running automated tests. Manual two-device checks are documented for the user to perform or explicitly request later.

---

Implementation method has not been selected. Review this plan and choose whether to execute it natively in this session or use subagent-driven implementation. The implementation workflow skill and a fresh code review are required after that choice.
