# MykoMaps Data Admin

Rails 8.1 admin interface for the open-data converter pipeline: per-source
schedules, manual downloads and uploads, dated download archives with
standard.csv output and diffs between downloads.

Default login: username `mykomaps`, password `admin`. A password change is
forced on first sign-in.

## How it works

- Data sources are the project dirs in the repo root (dirs with a `converter`
  script). `db:seed` registers new ones; sources found live on the servers at
  transition time (see ../TRANSITION.md) are enabled on `*/10 * * * *`.
- A Solid Queue recurring job (`ScheduleDispatchJob`, every minute) enqueues a
  `DataSourceRunJob` for each enabled source whose cron schedule is due.
- A run shells out to `bundle exec seod download` and `seod convert` in the
  project dir (exit 100 = no new data), then archives
  `original-data/` + `generated-data/standard.csv` + `meta.json` to
  `<DOWNLOADS_ROOT>/<source>/<YYYY-MM-DD_HHMMSS>/` and records a diff
  (added/removed/changed rows keyed on Identifier) against the previous
  download in `diff.txt`.
- Manual-upload sources take a file upload, which is copied into the project's
  `original-data/` before converting.

Environment:

- `OPEN_DATA_ROOT` - repo root containing the project dirs (default `..`)
- `DOWNLOADS_ROOT` - archive area (default `storage/downloads`)
- `SEOD_WRAPPER` - prefix for seod invocations (default `bundle exec`)

## Development

Ruby is pinned by `mise.toml` in the repo root. Install
[mise](https://mise.jdx.dev), then:

```bash
cd /path/to/open-data
mise install
cd admin
mise exec -- bundle install
mise exec -- bin/rails db:prepare db:seed
mise exec -- bin/dev
```

`mise exec --` runs a command with the pinned Ruby regardless of any rbenv or
asdf shims on the PATH. If mise is activated in your shell the prefix can be
dropped.

## Tests

```bash
cd admin
mise exec -- bin/rails test
mise exec -- bin/rubocop
```

The suite stubs `seod` with `test/stub_bin/seod` and points `OPEN_DATA_ROOT`
at a temp dir, so no network or real converters are needed.

## Deployment

Packaged for Cloudron from the repo root (Dockerfile, CloudronManifest.json,
start.sh). At runtime the converter projects are synced to `/app/data/open-data`
(downloads and generated data persist across updates), SQLite databases live
in `/app/data/storage` and archives in `/app/data/downloads`.
