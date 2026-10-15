# Admin Service Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins create and edit service details and illustrations, then show catalog changes to clients without restarting the app.

**Architecture:** Add service persistence to the existing clinic repository and create a dedicated admin service screen reachable through the admin route and side menu. Store images in a public Supabase Storage bucket whose writes are restricted to admins, and notify client service cards through the existing realtime `ServiceCatalog` stream.

**Tech Stack:** Flutter/Dart, `file_picker` already in `pubspec.yaml`, Supabase Postgres, Supabase Storage, Supabase Realtime, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-16-admin-service-management-design.md`

## Global Constraints

- Add and edit services only; do not delete or deactivate service rows.
- Use the existing `public.services` fields: name, description, price, duration, category, image URL, semantic label, display order, and existing rating.
- Keep image selection optional; preserve an existing illustration if an edit does not replace it, and use the client card's current fallback if a new service has no image.
- Do not add third-party dependencies; `file_picker` is already present.
- Restrict service image uploads and mutations to admins; allow public image reads for client service cards.
- Preserve existing booking snapshots and therapist references.

## Review Focus

- Empty service table: client catalog must display no services rather than showing stale seed items. Pin with `replaceFromBackend` test.
- Invalid service values: reject blank name/category, negative price, and zero or negative duration. Pin with form validation widget tests.
- Image boundary: reject empty, unsupported, or larger than 5 MiB image files before upload. Pin with image validation tests.
- Failed upload or row save: keep form input available for retry and preserve the old image URL; clean up a newly uploaded object after a failed row save. Pin form retry behavior with a fake repository widget test and review the upload/save/cleanup sequence in the repository implementation.
- Unauthorized writes: only the admin role can mutate service rows and image objects. Pin through migration policy review and Supabase role checks; do not rely on hidden UI controls as authorization.

---

### Task 1: Add service persistence and secure image storage

**Files:**
- Modify: `lib/data/repositories/clinic_repository.dart`
- Modify: `lib/data/repositories/supabase_clinic_repository.dart`
- Create: `lib/data/service_image_validator.dart`
- Create: `supabase/migrations/202610160003_admin_service_management.sql`
- Test: `test/service_image_validation_test.dart`

**Interfaces:**
- Produces `ClinicRepository.saveService(ClinicService service, Uint8List? illustrationBytes) -> Future<ClinicService>`.
- A blank service ID means insert; a nonblank ID means update. New IDs use a `svc_` prefix and a timestamp plus secure random suffix.
- Keep rating on edits; new services use a default rating of zero. New `displayOrder` is one greater than the current maximum supplied by the management screen.
- Produces `ServiceImageValidator.detect(Uint8List bytes) -> ServiceImageFormat`, where `ServiceImageFormat` is `jpeg`, `png`, or `webp`; throw `ArgumentError` for empty, unsupported, or greater-than-5-MiB bytes. Each format exposes `extension: String` and `contentType: String`.

- [ ] **Step 1: Add image validation tests** for JPEG, PNG, and WebP acceptance; empty or unsupported bytes; and files larger than 5 MiB.
- [ ] **Step 2: Run the focused test and confirm it fails** because the validator is not implemented.

Run: `flutter test test/service_image_validation_test.dart`
Expected: FAIL because the validation API or behavior is missing.

- [ ] **Step 3: Implement `ServiceImageValidator.detect` in `lib/data/service_image_validator.dart`.** Detect JPEG, PNG, and WebP by file signature; set `maxBytes = 5 * 1024 * 1024`; throw `ArgumentError` for empty, unsupported, or over-limit input.
- [ ] **Step 4: Add `saveService` to `ClinicRepository` and `SupabaseClinicRepository`.** For new rows, generate a `svc_` ID. Upload a selected image to `service-images/<service-id>/<unique-name>.<extension>`, save its public URL to `image_url`, and upsert the service fields. On row-save failure, remove the newly uploaded object and rethrow. On successful image replacement, remove the prior object only if its URL belongs to this bucket. Preserve existing image URL when no new bytes are supplied.
- [ ] **Step 5: Add the storage migration.** Create/configure public bucket `service-images` with a 5 MiB maximum and JPEG/PNG/WebP MIME types. Add a Storage policy that grants all object mutations in this bucket only when `public.current_app_role() = 'admin'`. Add `public.services` to `supabase_realtime` only if it is not already published. Do not alter existing service-table grants or row policies.
- [ ] **Step 6: Run the focused image validation test and confirm it passes.** Inspect the migration to confirm the bucket and policies are scoped to `service-images` and admin role.

Run: `flutter test test/service_image_validation_test.dart`
Expected: PASS.

---

### Task 2: Make the shared service catalog observable

**Files:**
- Modify: `lib/data/service_catalog.dart`
- Modify: `lib/main.dart`
- Test: `test/service_catalog_test.dart`

**Interfaces:**
- Produces `ServiceCatalog.listenable`, a `ValueListenable<List<Map<String, dynamic>>>` containing the current service maps.
- `ServiceCatalog.services` remains the read-only synchronous getter used by current selectors.
- `ServiceCatalog.replaceFromBackend(rows)` replaces and notifies even when `rows` is empty.

- [ ] **Step 1: Write catalog tests** for backend field mapping, listener notification on replacement, and replacement with an empty list.
- [ ] **Step 2: Run the focused test and confirm it fails** on the missing listenable and ignored empty replacement.

Run: `flutter test test/service_catalog_test.dart`
Expected: FAIL on the missing catalog notifier/empty-catalog behavior.

- [ ] **Step 3: Implement the catalog listenable and centralize `ClinicService` to service-map conversion.** Keep `connect()` subscribed to the backend stream and route startup rows through the same replacement method.
- [ ] **Step 4: Run the focused catalog tests and confirm they pass.**

Run: `flutter test test/service_catalog_test.dart`
Expected: PASS.

---

### Task 3: Build the admin service management screen

**Files:**
- Create: `lib/presentation/admin_dashboard_screen/service_management_screen.dart`
- Test: `test/service_management_screen_test.dart`

**Interfaces:**
- Produces `ServiceManagementScreen({super.key, ClinicRepository? repository})`; the optional repository allows tests to provide an in-memory fake, while app routes use `SupabaseClinicRepository` by default.
- The screen lists the repository's service stream and opens an add/edit form. Save goes through `ClinicRepository.saveService`.

- [ ] **Step 1: Write widget tests** for list rendering, add/edit form fields, validation errors, existing image preview, unchanged image on edit, and retaining the form after save failure.
- [ ] **Step 2: Run the focused widget test and confirm it fails** because the screen does not exist.

Run: `flutter test test/service_management_screen_test.dart`
Expected: FAIL because `ServiceManagementScreen` is missing.

- [ ] **Step 3: Implement the screen and form.** Include name, description, category, price, duration, and optional image illustration. Validate non-empty name/category, price >= 0, duration > 0, supported image bytes, and the 5 MiB limit. Preview selected/current image. Keep the editor open with values intact on failure; close it and show success only after save completes.
- [ ] **Step 4: Run the focused screen tests and confirm they pass.**

Run: `flutter test test/service_management_screen_test.dart`
Expected: PASS.

---

### Task 4: Add admin route and side-menu entry

**Files:**
- Modify: `lib/routes/app_routes.dart`
- Modify: `lib/presentation/admin_dashboard_screen/admin_dashboard_screen.dart`
- Test: `test/admin_service_management_navigation_test.dart`

**Interfaces:**
- Produces `AppRoutes.adminServiceManagement = '/admin-dashboard-screen/services'` and routes it to `ServiceManagementScreen`.
- Adds `_AdminSection.serviceManagement` labeled `Service Management` with a services icon. Only admin role sees and can open this route.

- [ ] **Step 1: Write navigation tests** that verify admin sees the menu item and cashier/client roles cannot enter the management route.
- [ ] **Step 2: Run the focused navigation test and confirm it fails** because the route/section is missing.

Run: `flutter test test/admin_service_management_navigation_test.dart`
Expected: FAIL because the route and side-menu section are missing.

- [ ] **Step 3: Add the route and side-menu section.** Follow the existing therapist-management `context.push` pattern. Extend the route redirect role allowlist so only admins can access the new route. Render no duplicate inline panel for the pushed section.
- [ ] **Step 4: Run the focused navigation test and confirm it passes.**

Run: `flutter test test/admin_service_management_navigation_test.dart`
Expected: PASS.

---

### Task 5: Refresh client service cards from catalog changes

**Files:**
- Modify: `lib/presentation/client_dashboard_screen/widget/popular_services_widget.dart`
- Test: `test/popular_services_widget_test.dart`

**Interfaces:**
- Consumes `ServiceCatalog.listenable` and rebuilds the displayed service cards from the current catalog list.
- Existing `onBookService(Map<String, dynamic>)` behavior remains unchanged.

- [ ] **Step 1: Write widget tests** that a service card updates after catalog replacement and disappears after an empty replacement.
- [ ] **Step 2: Run the focused test and confirm it fails** because the widget does not listen to catalog changes.

Run: `flutter test test/popular_services_widget_test.dart`
Expected: FAIL because service changes do not trigger a rebuild.

- [ ] **Step 3: Wrap the service-card rendering in `ValueListenableBuilder`** using `ServiceCatalog.listenable`; keep the existing responsive grid/list presentation and booking callback.
- [ ] **Step 4: Run the focused widget test and confirm it passes.**

Run: `flutter test test/popular_services_widget_test.dart`
Expected: PASS.

---

### Task 6: Review deployment and end-to-end behavior

**Files:**
- Review: all files above and `docs/superpowers/specs/2026-10-16-admin-service-management-design.md`

- [ ] **Step 1: Run the full project test suite.**

Run: `flutter test`
Expected: PASS with no failures.

- [ ] **Step 2: Run static analysis.**

Run: `flutter analyze`
Expected: No new diagnostics caused by this feature.

- [ ] **Step 3: Review the SQL migration and exercise the feature in two sessions.** Sign in as admin to add and edit services with and without image changes; confirm non-admin writes are denied. Keep a client dashboard open in a second session and confirm it reflects the new/edited service. Confirm booking and walk-in screens can use the new service and prior bookings retain their saved name and price.
- [ ] **Step 4: Apply the migration to the linked Supabase project** with `npx --yes supabase db push` before testing image uploads against the deployed backend.

