# Admin Service Management Design

## Goal

Give admins a dedicated side-menu screen to add services and edit existing service details, including an illustration that appears in the client booking catalog. Clients should see catalog changes without restarting the app.

## Scope

- Add a **Service Management** item to the admin side menu.
- List services and provide add and edit forms.
- Service fields: name, description, category, price, duration, and illustration. Preserve the existing image when editing without choosing a replacement; allow a new service to use the existing image fallback if no illustration is chosen.
- Persist service rows to the existing `public.services` table. The table already contains these fields and admin-only row policies.
- Upload chosen illustrations to a public `service-images` Supabase Storage bucket. Public reads let client screens display the files; authenticated admin policies restrict upload, update, and removal.
- Save the uploaded image's public URL to `services.image_url`. Replace an old uploaded image only after the new URL has been saved successfully; keep existing images if saving fails.
- Notify the in-app service catalog when Supabase emits service changes so client service cards refresh while open.
- Keep current service records, historical bookings, therapist specialty references, and pricing in existing booking records unchanged.

## Not in scope

- Deleting or deactivating services. Existing bookings and therapist specialty rows can reference service IDs, so removal needs a separate lifecycle decision.
- Changes to booking payment, therapist assignment, or booking status rules.
- New third-party dependencies. The project already includes `file_picker` for selecting image bytes.

## Design

### Admin screen

Add a dedicated `ServiceManagementScreen` and connect it to the admin dashboard's side menu and section routing, following the existing therapist management navigation pattern. The screen reads the Supabase service stream and shows each service's current name, category, price, duration, and illustration, with actions to add a service or edit one.

The add/edit dialog validates a non-empty name and category, a non-negative price, and a positive duration. It includes an image preview and file picker. On edit, leaving the image unchanged preserves the current URL. If a new service has no selected image, the client cards use their existing category fallback.

### Data and image storage

Extend `ClinicRepository` with a service save operation and implement it in `SupabaseClinicRepository`. Store the service fields in `public.services`; assign a unique `svc_` ID for new rows and preserve the ID for edits. Upload image bytes under a unique object name in the `service-images` bucket and save its public URL to `image_url`.

Add a Supabase migration to create or configure the public image bucket with a bounded image size and supported image MIME types, permit public image reads, and restrict storage mutations to admins using the existing `current_app_role()` check. The migration also adds `public.services` to the `supabase_realtime` publication if it is not already present. No new service columns are needed.

If an edit replaces an image, upload first, save the row second, then remove the old object. If the row save fails, remove the newly uploaded object and retain the prior service data. If an add/edit changes no image, don't touch storage.

### Client catalog updates

Keep `ServiceCatalog.connect()` as the realtime source of service rows, but expose catalog changes through a `ValueListenable` (or equivalent notifier). Update client service cards to listen to that notifier so adds and edits redraw the visible catalog. Treat an empty backend result as an empty catalog instead of silently restoring seeded services.

### Access and errors

Only the existing admin role can open the management screen; Supabase row and Storage policies remain the enforcement boundary. Show save/upload failures in the form and preserve entered values so the admin can retry. Show a useful empty state when there are no service rows.

## Verification

- Review admin create and edit behavior with and without a replacement image.
- Confirm non-admin users cannot write service rows or service images through Supabase policies.
- Confirm a client dashboard open in another session shows a new or edited service after the realtime update.
- Confirm bookings and walk-in service selectors receive the updated service values on their next rebuild/reload, while existing booking snapshots retain their original service name and price.
- Check Flutter static analysis and run the project tests after implementation.

## Deployment

Because this design adds a Storage bucket and policies, implementation includes a migration. Apply pending migrations to the linked Supabase project with `npx --yes supabase db push` before relying on image uploads in deployed sessions.
