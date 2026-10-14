# SDD ledger — plan: docs/superpowers/plans/2026-10-14-client-chatbot.md

Ruling: Work in the current master checkout — the user earlier explicitly chose the current workspace to preserve in-progress Supabase edits — cost if wrong: feature changes coexist with unrelated uncommitted work and need careful diff review.
Ruling: Do not add or run automated tests — higher-priority developer instructions prohibit tests unless the user asks for testing/verification — cost if wrong: runtime defects may be found only after the user's own run.
Pre-flight: Task 1 produces the HTTP request/reply contract; Task 2 consumes that contract and emits `ClientChatMessage`; Task 3 consumes the repository/model in its chat screen. No conflicting signatures found.
Task 1: implemented; fresh review findings fixed and re-reviewed. No tests run per higher-priority instruction.
Task 2: implemented; authenticated Supabase Function invoke, bounded history, friendly errors. No tests run.
Task 3: implemented; client-only route, ephemeral chat UI, dashboard FAB above Book Now. No tests run.
Task 4: local handoff prepared. GEMINI_API_KEY presence was shown in the user's Supabase screenshot; deployment remains pending explicit user authorization.
Review: no critical authorization or cross-user data isolation blocker found. Residual privacy note: a client can fabricate recent chat history to request their own booking context; backend RLS still scopes all queried rows to that client. Booking context is otherwise gated to explicit booking intent or immediate relevant follow-up.
No automated tests, analyzer, build, or deployment commands were run.
