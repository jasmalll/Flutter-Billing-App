# CaterPro Supabase Setup (Malayalam)

## App-ന്റെ save/sync രീതി

1. Save അമർത്തുമ്പോൾ ആദ്യം data ഫോണിന്റെ/browser-ന്റെ local storage-ൽ save ചെയ്യും.
2. അതിനു ശേഷം pending cloud-sync queue-യിൽ ആ record ചേർക്കും.
3. Supabase login/network/configuration ശരിയാണെങ്കിൽ cloud-ലേക്ക് sync ചെയ്യാൻ ശ്രമിക്കും.
4. Sync പരാജയപ്പെട്ടാൽ pending item local storage-ൽ തുടരും; app restart/sign-in സമയത്തും signed-in ആയിരിക്കുമ്പോൾ ഏകദേശം 30 സെക്കൻഡ് ഇടവേളകളിലും retry ചെയ്യും.
5. App-ൽ local save വിജയിച്ചാലും cloud sync വിജയിച്ചുവെന്ന് അർത്ഥമില്ല. Cloud sync ഉറപ്പാക്കാൻ `Other → Cloud sign in` വഴി sign in ചെയ്ത് pending queue വിജയകരമായി തീർന്നിട്ടുണ്ടെന്ന് പരിശോധിക്കുക.

## 1. SQL schema സജ്ജമാക്കുക

1. Supabase Dashboard തുറന്ന് നിന്റെ project തിരഞ്ഞെടുക്കുക.
2. **SQL Editor → New query** തുറക്കുക.
3. Repository-യിലെ `supabase/schema.sql` മുഴുവൻ copy ചെയ്ത് SQL Editor-ൽ paste ചെയ്യുക.
4. **Run** അമർത്തുക. Error വന്നാൽ അത് പരിഹരിക്കുന്നതുവരെ app-ൽ cloud sync പരീക്ഷിക്കരുത്.

ഈ schema `master_staff`, `event_bills`, `inventory_counts`, `event_settlements` tables-ഉം organization അടിസ്ഥാനത്തിലുള്ള RLS policies-ഉം സൃഷ്ടിക്കുന്നു.

## 2. Supervisor account, organization ID

1. Supabase Dashboard → **Authentication → Users** തുറക്കുക.
2. നിനക്കായി supervisor user സൃഷ്ടിക്കുക (Sign up enabled ആണെങ്കിൽ app-ൽ sign up ചെയ്യാനും കഴിയും; production-ൽ അറിയാത്തവർക്ക് account ഉണ്ടാക്കാൻ അനുവദിക്കരുത്).
3. `org_id` എന്ന trusted **app_metadata** value ഒരു valid UUID ആയിരിക്കണം. ഉദാഹരണ UUID മാത്രം: `11111111-1111-4111-8111-111111111111` — സ്വന്തം organization-ന് പുതിയ UUID സൃഷ്ടിക്കുക; ഈ example production-ൽ ഉപയോഗിക്കരുത്.
4. Supabase-ന്റെ trusted admin mechanism ഉപയോഗിച്ച് ആ UUID supervisor user-ന്റെ `app_metadata.org_id`-ൽ സജ്ജമാക്കുക. User-editable `user_metadata`-ൽ വെച്ചാൽ ഈ RLS policy അത് അംഗീകരിക്കില്ല.
5. App-ൽ ആ supervisor account ഉപയോഗിച്ച് sign in ചെയ്യുക.

**Security:** `service_role` / `sb_secret_...` key client app-ലോ GitHub-ലോ ഒരിക്കലും ഇടരുത്. `app_metadata.org_id` മാറ്റാൻ service-role/admin access ആവശ്യമായാൽ അത് server-side/admin tool-ൽ മാത്രം ашигിക്കുക.

## 3. URL, public key ഉപയോഗിച്ച് Flutter പ്രവർത്തിപ്പിക്കുക

Project URL-യും publishable/anon public key-യും terminal command-ൽ നൽകുക. ഇവിടെ placeholder values നിന്റെ സ്വന്തം values കൊണ്ട് മാറ്റണം; chat-ൽ key അയക്കേണ്ടതില്ല.

### Windows PowerShell

```powershell
flutter pub get
flutter run --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_PUBLISHABLE_OR_ANON_KEY"
```

Release APK:

```powershell
flutter build apk --release --dart-define=SUPABASE_URL="https://YOUR_PROJECT.supabase.co" --dart-define=SUPABASE_ANON_KEY="YOUR_PUBLISHABLE_OR_ANON_KEY"
```

`SUPABASE_ANON_KEY` എന്ന പേരാണ് code ഉപയോഗിക്കുന്നത്; Supabase dashboard-ൽ കിട്ടുന്ന client-side publishable/anon public key ആണ് value. Secret/service-role key ഉപയോഗിക്കരുത്.

## 4. GitHub Pages ഉപയോഗിക്കുന്നുവെങ്കിൽ

GitHub repository → **Settings → Secrets and variables → Actions**-ൽ രണ്ട് repository secrets ചേർക്കുക:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

ശേഷം `main` branch-ലേക്ക് push ചെയ്യുക അല്ലെങ്കിൽ Actions workflow manually run ചെയ്യുക. Workflow-ൽ `/billing_app/` base path ഉപയോഗിക്കുന്നു.

## 5. നിർബന്ധമായും test ചെയ്യുക

1. Cloud sign in ചെയ്യുക.
2. ഒരു test event, staff record, inventory update, settlement എന്നിവ save ചെയ്യുക.
3. Supabase Table Editor-ൽ records എത്തിയിട്ടുണ്ടോ പരിശോധിക്കുക.
4. Internet താൽക്കാലികമായി ഓഫ് ചെയ്ത് മറ്റൊരു test update save ചെയ്യുക; local app-ൽ data നിലനിൽക്കുന്നുണ്ടെന്ന് ഉറപ്പാക്കുക.
5. Internet തിരികെ ഓൺ ചെയ്യുക; pending queue retry ചെയ്യാൻ അനുവദിക്കുക.
6. മറ്റൊരു device/browser-ൽ അതേ organization account ഉപയോഗിച്ച് sign in ചെയ്ത് data പരിശോധിക്കുക.
7. രണ്ട് വ്യത്യസ്ത organization accounts ഉപയോഗിച്ച് RLS test ചെയ്യുക; മറ്റൊരു organization-ന്റെ records ഒരിക്കലും ലഭിക്കരുത്.
8. Production-ന് മുമ്പ് JSON backup export ചെയ്ത് വേറൊരു സ്ഥലത്ത് സൂക്ഷിക്കുക.

## പ്രധാന പരിമിതികൾ

- Local storage `SharedPreferences` ആണ്; app data clear/uninstall ചെയ്താൽ device-ലെ local copy നഷ്ടപ്പെടാം. Cloud sync/backup വിജയിച്ചിട്ടുണ്ടെന്ന് പരിശോധിക്കുക.
- ഈ schema-യിൽ organization-ന് ഒരു event bill per date മാത്രമേ cloud-ൽ store ചെയ്യാൻ കഴിയൂ (`unique (organization_id, event_date)`).
- Browser/device-ൽ offline state-ൽ save ചെയ്ത data cloud-ലേക്ക് sync වීමට app-ൽ valid login/session தேவை.
- Sync queue failed item-കൾ സൂക്ഷിക്കുകയും retry ചെയ്യുകയും ചെയ്യും; എന്നാൽ database schema/RLS/auth error ഉണ്ടെങ്കിൽ അത് സ്വയം പരിഹരിക്കില്ല.
