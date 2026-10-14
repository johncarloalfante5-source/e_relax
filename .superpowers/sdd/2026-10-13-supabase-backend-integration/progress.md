# SDD ledger — plan: docs/superpowers/plans/2026-10-13-supabase-backend-integration.md

Pre-flight: User approved native implementation in the current workspace. Checkout is `master` and was already dirty before this task; preserve unrelated edits.

Pre-flight interfaces:
- Task 1 produces profiles/services/therapists/duty schema consumed by Tasks 2 and 3: schema must use stable service IDs and roles exactly `client`, `admin`, `cashier`, `therapist`.
- Task 2 produces Supabase client/auth profile consumed by Tasks 3–7: downstream repositories must use authenticated user ID and role, never email-string routing.
- Task 3 produces persisted services and therapists/duty availability consumed by Tasks 4 and 5: `therapist_id`, service references, and date availability must be shared.
- Task 4 produces booking/payment/notification records consumed by Tasks 5–7: transactions, history and status changes must be atomic and idempotent.
- Task 5 produces walk-ins and financial ledger consumed by Tasks 6–7: checkout and completion timestamps are distinct; checkout is allowed at any time.
- Task 6 consumes Task 4 and Task 5 records: reports query saved ledger and completion timestamps only.
- Task 7 consumes all role-aware repositories: subscriptions trigger reloads and never bypass RLS.

Ruling: Skip the execution skill's automated baseline/task test commands because the active developer instruction prohibits adding or running tests unless the user asks. The plan itself records this constraint; no tests are being added or run.

Status: implementation not started.
