# Staff Billing Platform (Flutter)

A local-first staff billing and catering operations app for event ledgers, manpower, attendance/wages, inventory counts, SP/CP settlements, PDF exports, calendar archive, and optional Supabase cloud sync.

## Features

- **Reporting:** staff roster, attendance, wage presets/custom wages, and staff grouping.
- **Outing:** event ledger, setting bill, named other-expense breakdown, TA multiplier, and PDF export.
- **Calendar:** archived event reload and JSON backup/restore.
- **Other Operations Hub:** historical overview, Manpower directory, Total Counts with station allocations, and date-based SP/CP settlement calculations.
- **Offline-first storage:** every save is written to local storage first; a durable pending-sync queue is then updated.
- **Automatic retry:** queued writes survive app restarts and retry after sign-in/startup and periodically while signed in.
- **Supabase:** authenticated organization-scoped sync for event bills, master staff, inventory, and settlements; deletes are queued too.

## Local development

Use a Flutter SDK compatible with the `environment.sdk` value in `pubspec.yaml`, then run:

```bash
flutter pub get
 dart format lib test
flutter analyze
flutter test
flutter run
```

The app remains usable without Supabase credentials. Local records are stored using SharedPreferences. Export the JSON backup to a location outside the app/device if you need disaster recovery; an in-app local copy alone will not survive app-data deletion or device loss. The export/restore flow is a JSON file workflow, **not a direct Google Drive API integration**.

## Supabase setup

1. Create a Supabase project.
2. Run [`supabase/schema.sql`](supabase/schema.sql) in the Supabase SQL Editor.
3. Configure Supabase Auth and provision a supervisor user with a trusted `app_metadata.org_id` UUID. The SQL RLS policies intentionally use trusted `app_metadata`, not user-editable metadata.
4. Use the project URL and **publishable/anon public key** at build time. This project reads the key from the `SUPABASE_ANON_KEY` Dart define; do not use a secret/service-role key:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

5. Open **Other → Cloud sign in** and sign in with the provisioned supervisor account.

Never put a Supabase service-role key in Flutter code, GitHub Pages, or any client build. The anon key is designed for client use only when RLS is correctly configured. Cloud sync is local-first and queued for retry, but it still requires a successful sign-in, a valid `app_metadata.org_id`, correct RLS policies, and a working network. Validate recovery and conflict behavior against your own Supabase project before using it for production records. The current cloud schema allows one event bill per organization per date.

## GitHub Pages deployment

The workflow in `.github/workflows/deploy.yml` builds the web app with `/billing_app/` as its base path and deploys it to GitHub Pages.

1. In the GitHub repository, open **Settings → Pages** and select **GitHub Actions** as the deployment source.
2. If you want Supabase cloud sync on the live website, add repository **Actions secrets** named `SUPABASE_URL` and `SUPABASE_ANON_KEY`. If they are absent, the app builds in local/offline mode.
3. Push to `main`, then check **Actions** for the build/deploy result.
4. The expected website URL is `https://jasmalll.github.io/billing_app/`.

## Before production

- Run `flutter analyze`, `flutter test`, and `flutter build web --release --base-href /billing_app/` with the supported Flutter SDK.
- Verify backup/restore using a copy of real test data before restoring over important records.
- Verify Supabase RLS using at least two test organizations and confirm each can access only its own records.
- Decide whether multiple events on the same date are allowed before changing the cloud uniqueness key.
- Keep a separate backup outside the phone/browser storage.
