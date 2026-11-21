# soundLInk download page

Live production URL: https://soundlink-download.vercel.app/

Static public page deployed to Vercel, with public read-only release metadata from the existing Supabase project. APK bytes are served by the public GitHub release, so no account is needed to download.

- Vercel team: MacroView (`team_Evei6XHnBnCMJfvfNSXk0Agn`)
- Vercel project: soundlink-download (`prj_sQeRI5VcBkivbq80SOhvot4fom2H`)
- Supabase project: `gwpfujataqyehcxcwndm`
- Table: `public.soundlink_releases`; RLS enabled, published releases readable by anon/authenticated, no public mutation grants.
- `config.json` contains only the intentionally public publishable API key, never a service-role or secret key.
- `supabase/schema.sql` records the applied schema and original release metadata. It is a reference, not a script to rerun against an existing table.

The page uses native fetch against Supabase REST; there are no runtime package dependencies and no build step. Preview with `python3 -m http.server 8890 --directory web` from the repository root. Vercel deployments use the files in this directory as the static root. Public download links remain functional if the metadata lookup is unavailable. No analytics or personal data collection is added.

Update releases through a trusted Supabase admin connection: upload the APK to GitHub first, verify its SHA-256 and size, then insert a new published release row. Never add anonymous writes. The site fetches the newest published release. The HTML's fallback APK should be updated alongside new release metadata so downloads remain useful during a database outage.
