# Real-Time Booking Notifications Design

## Status

Design specification for review. No implementation changes are included in
this document's creation. Implementation planning starts after the user
reviews and approves this specification.

## Goal

Keep clients and operations staff informed as an online booking moves through
payment review, confirmation, check-in, service, and balance collection. Show
real-time in-app notifications and navigation indicators that point to unread
updates or work still requiring staff action.

## Approved behavior

- A new client booking creates a notification for the admin and a badge on the
  admin **Bookings** menu.
- A client cancellation notifies the admin and updates the admin's booking
  work queue.
- Booking and payment changes notify the client. The client sees unread
  booking notifications in the bell and a badge on the **Bookings** bottom
  navigation tab.
- The admin bell displays recent admin notifications. The admin **Bookings**
  menu badge represents unread booking notifications.
- Staff work counts remain separate from notification counts. **Payment
  Verification** shows bookings awaiting proof review. **Checkout** shows
  checked-in, in-progress, or completed online bookings with a remaining
  balance.
- Indicators update live while the relevant dashboard is open and notifications
  remain persisted across sign-ins and devices.
- This scope is in-app only. Device push notifications are excluded.

## Current project findings

- `public.notifications` stores per-user messages, `read_at`, `booking_id`,
  and unique event keys. RLS limits users to their own notification rows.
- `PaymentBookingStore.initialize()` already loads and streams the signed-in
  user's notifications. Booking rows are also streamed with Supabase Realtime.
- Client notification bell opens `ClientNotificationsScreen`; the client
  bottom-navigation **Bookings** tab has no unread badge.
- The admin dashboard has a no-op notification bell. Its sidebar has
  **Bookings**, **Payment Verification**, **Online In Progress**, and
  **Checkout** sections.
- Existing SQL functions notify the client about verified/rejected payment,
  confirmation/cancellation, and balance collection. Check-in, service start,
  and service completion do not create client notifications.
- `public.notifications` is already included in the Supabase Realtime
  publication by the existing report migration.
- Migrations live in `supabase/migrations/` and are applied to the hosted
  project with `npx --yes supabase db push`.

## Approaches considered

1. **Persist notifications in the existing table and stream changes with
   Supabase Realtime (recommended).** This reuses the app's notification model,
   RLS, history, and subscriptions. Database changes create notification rows;
   Flutter derives unread and work-queue badges from live data.
2. **Use transient Realtime broadcasts.** This avoids persisting additional
   events but loses notifications when the recipient is offline and cannot
   support durable unread counts.
3. **Add device push notifications.** This can reach a closed app but requires
   push-provider configuration and platform permissions beyond the requested
   in-app flow.

## Architecture and data flow

### Database events

Use a new migration after the current latest migration. Add database-side
notification creation for events that currently lack it:

- On online booking creation, create a `new_booking:<booking-id>` notification
  for each profile whose role is `admin`. It includes service, client, and
  appointment details.
- On a booking status change to `checkedIn`, `inProgress`, or `completed`,
  create a client notification describing the new status. Existing payment
  verification, rejection, confirmed/cancelled, and balance-collected
  notifications remain the source for those events; avoid duplicate messages.
- When the client cancels, notify admin profiles using a distinct
  `client_cancelled:<booking-id>` event key. Staff-initiated cancellations do
  not generate a notification to the same admin as a new work item.
- Continue using the existing `notifications` RLS, unique `(user_id,
  event_key)` constraint, owner-read policy, and Realtime publication.
- Notification inserts must be part of the same database transaction as the
  booking event, so UI state cannot claim an event that failed to persist.

### Flutter notification state

- Generalize notification lookup/counting to the authenticated user ID rather
  than assuming every notice belongs to a client.
- Keep unread notice counts distinct from staff action counts.
- Provide a repository/store operation to mark the current user's
  booking-linked notifications read when opening the relevant bookings view;
  existing per-notification read behavior in the client notification page is
  retained.
- A failed subscription or refresh preserves the last loaded data and does not
  fabricate a cleared unread state.

### Client indicators

- Show a numeric badge on the **Bookings** bottom-navigation destination for
  unread notifications linked to bookings.
- Opening **Bookings** marks booking-linked notifications read for that
  client, clearing its badge. The bell continues to link to the existing
  notifications page and can mark individual notifications read there.
- New payment, status, cancellation, and balance updates arrive through the
  existing notification stream without requiring app restart.

### Admin indicators and bell

- Show a badge on the admin notification bell for unread admin notifications.
- Opening the bell displays a recent-notifications panel. Selecting a booking
  notification marks it read and opens the **Bookings** section.
- Show an unread-booking-notification badge on the **Bookings** sidebar item.
  Entering that section marks booking-linked admin notifications read.
- Show a separate staff-action count on **Payment Verification** using
  bookings with pending verification.
- Show a separate staff-action count on **Checkout** using verified online
  bookings in `checkedIn`, `inProgress`, or `completed` state with a positive
  remaining balance.
- Counts update from the existing live booking and notification streams, not
  from local timers or manually refreshed snapshots.

## Security and privacy

- Notifications are written by validated database functions or narrowly
  scoped triggers with a fixed `search_path`; clients cannot write arbitrary
  notification rows.
- Admin recipients are resolved from `public.profiles` where role is `admin`;
  do not expose notifications to other clients.
- Client notifications remain visible only to their owner through the current
  RLS policy.
- Notification text should include only booking details needed to identify
  the update and should not contain payment proof contents or secrets.

## Acceptance criteria

1. A new online booking creates exactly one durable admin notification and the
   admin sees the bell and **Bookings** badges update live.
2. Payment verification/rejection, check-in, service start/completion,
   cancellation, and balance collection notify the client without duplicate
   status messages.
3. The client sees a live unread badge on **Bookings**; opening that tab clears
   the booking-notification badge, and the bell page can mark individual
   notices read.
4. The admin **Payment Verification** and **Checkout** badges reflect current
   actionable booking counts independently of unread notification counts.
5. Notification history and unread state persist across sign-in and device
   changes.
6. Notification data remains protected by existing owner-based RLS.
7. No device push notification setup is introduced.

## Out of scope

- Android, iOS, or browser push notifications.
- Therapist or cashier-specific notification inboxes.
- Changing booking/payment rules or introducing a new notification service.
- Notifications for walk-in events.
