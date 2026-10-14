# Supabase setup

This folder contains versioned schema migrations for E-Relax. A Flutter project URL and publishable key do not grant this app permission to apply database DDL. Apply migrations from the Supabase CLI linked to your project or paste reviewed migration SQL into the Supabase SQL Editor.

1. Install the Supabase CLI and run `supabase login`.
2. Link the project with `supabase link --project-ref rafzcrnoagjvoflarkpw`.
3. Review the SQL, then apply using `supabase db push`.
4. Create the initial admin account through Supabase Auth, then promote that account using the commented SQL at the end of the first migration. Never allow public client registration to choose a staff role.
5. Keep payment proof objects in a private bucket. Migration 2 creates the bucket and object policies; verify they are present before enabling proof uploads.

Create `.env.supabase.json` from `.env.supabase.example`, then place your project's URL and publishable key in that ignored local file. Run Flutter with `flutter run --dart-define-from-file=.env.supabase.json`. Only the Supabase URL and publishable key belong in the app. Never put a service-role or secret key in Flutter.

For therapist sign-in, first create the user's Auth account and promote/link the user through a trusted admin workflow. Set `therapists.auth_profile_id` to that user's profile UUID using the Supabase SQL Editor. A therapist record's optional email field alone does not grant account access.

After applying all migrations, use two authenticated devices to check: client sign-up and sign-in; therapist duty visibility in online booking; submit proof and verify/reject/resubmit; notification and receipt status; walk-in timer and early checkout; completed appointment balance collection; and sales/service report totals plus both PDF exports. Reports include captured deposits only after verification and balances/walk-ins only after collection.

The migrations do not recover records from the prototype's in-memory stores. Existing demonstration or real records must be deliberately imported. Use separate Supabase projects for development and production, and test role isolation before using real client data.
