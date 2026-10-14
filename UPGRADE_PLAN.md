# Staff Billing Platform — Upgrade Status

## Implemented in the current source

- Four primary areas: Reporting, Outing, Calendar, and Other.
- Local-first event billing/archive with optional best-effort Supabase synchronization.
- Manpower directory and strict normalized **Name + Phone** wage suggestion matching. Suggestions do not change the ₹430 default until a supervisor taps the amber chip.
- Outing named Other Expense rows and PDF breakdown.
- Calendar JSON backup/restore with legacy bill-only backup compatibility.
- Other Operations Hub with overview metrics, master inventory, station allocation matrix, and date-based SP/CP settlement allowances.
- Calculation PDF with SP/CP tables, expense balance panel, totals, and signature lines.
- Supabase organization-scoped RLS schema and optional build-time URL/anon-key configuration.
- GitHub Pages workflow using `/billing_app/` base href, now with a Flutter test step and optional Supabase Actions secrets.
- Restore validation now parses all backup sections before writing, rejecting malformed archives before replacing existing records.

## Deployment setup still required

1. In GitHub repository Settings → Pages, use GitHub Actions as the deployment source.
2. For cloud sync on the website, add Actions secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Leave them unset only if local/offline mode is intended.
3. In Supabase, apply `supabase/schema.sql`, configure Auth, and assign trusted `app_metadata.org_id` to the supervisor user.
4. Confirm the cloud schema's one-event-per-organization-per-date rule matches operational needs.

## Validation required before production

This environment does not include the Flutter/Dart SDK, so Flutter analysis, tests, and web build could not be executed here. Run these commands on a machine with the compatible SDK:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build web --release --base-href /billing_app/
```

Then test restore using a copy of real data and verify Supabase RLS with two separate test organizations. Do not deploy service-role keys to any client. JSON export is not a direct Google Drive API integration; copy the exported file to an external backup location.
