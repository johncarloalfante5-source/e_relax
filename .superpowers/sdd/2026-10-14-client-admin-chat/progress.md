# SDD ledger — plan: docs/superpowers/plans/2026-10-14-client-admin-chat.md

Pre-flight: current workspace is authorized by prior user instruction; shared interfaces align across SQL RPCs, repository methods, client thread/entry, and admin inbox.

Ruling: Automated tests and analyzer/build checks will not be added or run — higher-priority developer instruction forbids them unless the user requests verification; cost: implementation cannot claim compile/runtime verification.

Ruling: Supabase migration will be created locally but not pushed — deployment changes the hosted database and is explicitly a later user-run step in the approved plan; cost: chat remains unavailable in production until migration is applied.

Implemented the local migration, immutable models, Supabase repository, shared chat thread with older-message paging/retry/read state, client dashboard entry/unread badge, role-gated route, admin inbox/unread metric, and live refresh subscriptions. Fresh read-only code review is pending. No tests, analyzer, or build run; hosted migration not pushed.

Ruling: SDD workspace helper required bash, unavailable in this PowerShell environment; the workspace was created manually and the plan path recorded.

Read-only reviewer checked the changed feature and flagged two issues; both were fixed and re-reviewed. No new obvious issues reported. Implementation inspection is complete; no compile/runtime verification claimed.
