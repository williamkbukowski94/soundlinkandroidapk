create table public.soundlink_releases (
  release_key text primary key,
  version text not null,
  channel text not null check (channel in ('test','stable')),
  filename text not null,
  download_url text not null check (download_url like 'https://github.com/williamkbukowski94/soundlinkandroidapk/releases/download/%'),
  size_bytes integer not null check (size_bytes > 0),
  min_android integer not null,
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  published boolean not null default false,
  published_at timestamptz not null default now()
);
alter table public.soundlink_releases enable row level security;
revoke all on public.soundlink_releases from anon, authenticated;
grant select on public.soundlink_releases to anon, authenticated;
create policy "Read published soundlink releases" on public.soundlink_releases for select to anon, authenticated using (published = true);
insert into public.soundlink_releases (release_key, version, channel, filename, download_url, size_bytes, min_android, sha256, published)
values ('android-0.1.0','0.1.0','test','soundLInk-android-0.1.0.apk','https://github.com/williamkbukowski94/soundlinkandroidapk/releases/download/v0.1.0/soundLInk-android-0.1.0.apk',126156,10,'dd3a8b8a935e7bee57cf0555d8765e797ffad7ae5d8828eb3da90814b035688d',true);
