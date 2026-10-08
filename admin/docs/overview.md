# Overview

The admin app runs the open-data converters on a schedule, keeps every
download, builds unified CSVs for projects that combine several sources,
and turns those into MykoMaps datasets. It is a Rails 8.1 app with SQLite
databases, Solid Queue for background jobs (running inside puma) and no
external services.

## Concepts

- **Data source**: one converter directory in the repo root (any directory
  with a `converter` script). Type `auto` when the directory also has a
  `downloader`, otherwise `manual`: the data file is uploaded by hand.
- **Run**: one download and convert of a source. Statuses: queued, running,
  succeeded, no changes, failed. Triggered by the schedule, the "Download
  now" button or an upload.
- **Project**: a map or dataset built from one or more sources, for example
  the Cooperative World Map. A source may belong to several projects.
- **Unified CSV build**: the latest `standard.csv` of each source in a
  project, cleaned and merged into one CSV with deduplicated rows. Only
  projects with a `unify:` section in `db/projects.yml` have builds.
- **MykoMaps dataset**: a zip of `config.json`, `locations.json`,
  `searchable.json`, `items/` and assets, built from a unified CSV and the
  project's map config in `admin/mykomaps/<key>/`.
- **Secret**: an API key or password a converter needs, saved encrypted and
  passed to the converter as a `PASSWORD__*` environment variable.

## How a run works

1. `ScheduleDispatchJob` runs every minute and queues a `DataSourceRunJob`
   for each enabled source whose cron schedule has fired since its last run.
2. The job runs `seod download` then `seod convert` in the source directory
   with a clean environment: the app's bundler settings are stripped, the
   saved secrets are added, and `SEOD_CONFIG=production.conf` is set when
   the source has that file.
3. `seod download` exiting 100 means the upstream data has not changed. The
   run is recorded as "no changes" and nothing is archived.
4. Otherwise `original-data/`, `generated-data/standard.csv` and `meta.json`
   are copied to a dated archive directory and the new `standard.csv` is
   diffed against the previous download, keyed on the Identifier column.
   Added, removed and changed row counts appear on the source page.

A manual upload copies the uploaded file into the source's `original-data/`
under the filename its conf expects (`ORIGINAL_CSV`), then runs convert.

## Unified CSV builds

`ProjectBuilder` reads the latest `standard.csv` of every source in the
project's unify settings, cleans each one (`UnifiedCsv::Cleaner`), merges
them (`UnifiedCsv::Unifier`, matching on the columns in `match_on`, taking
each field from the highest-priority source) and stamps every row with
Created At and Updated At carried over from the previous build. Both steps
are ports of the data-pipelines TypeScript and produce the same bytes. The
build archive holds `meta.json`, `cleaned/`, `unified.csv` and `diff.txt`.

## Where files live

Paths are set by environment variables; the defaults are relative to
`admin/`. The Cloudron image sets them under `/app/data`.

- `OPEN_DATA_ROOT` (default `..`): the converter directories
- `DOWNLOADS_ROOT` (default `storage/downloads`):
  `<source>/<YYYY-MM-DD_HHMMSS>/` per archived run
- `BUILDS_ROOT` (default `storage/builds`): `<project>/<timestamp>/` per
  unified CSV build and `<project>/datasets/<timestamp>/dataset.zip` per
  dataset
- `DATA_BUILDER_ROOT` (default `storage/data_builder`): `uploads/` for CSVs
  staged in the dataset builder (swept after 24 hours) and `builds/` for its
  zips
- `storage/`: the SQLite databases (app, cache, queue, cable)

Other variables: `SEOD_WRAPPER` (prefix for seod, default `bundle exec`),
`SEOD_CONFIG` (conf file for the converters, overrides the production.conf
default), `RAILS_LOG_LEVEL`, `PORT`, `RAILS_MAX_THREADS`,
`SOLID_QUEUE_IN_PUMA` (set to run jobs inside puma).

## Recurring jobs

Defined in `config/recurring.yml`:

- `ScheduleDispatchJob` every minute
- `DiskUsageJob` every hour: measures downloads and builds for the
  dashboard card
- `DataBuilder::CleanupJob` daily at 03:00: deletes staged uploads older
  than 24 hours; built zips are kept
